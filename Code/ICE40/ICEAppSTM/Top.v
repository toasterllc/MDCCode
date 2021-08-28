`include "Util.v"
`include "ICEAppTypes.v"
`include "TogglePulse.v"
`include "ClockGen.v"
`include "AFIFOChain.v"
`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    input wire          ice_st_spi_clk,
    input wire          ice_st_spi_cs_,
    inout wire[7:0]     ice_st_spi_d,
    output wire         ice_st_spi_d_ready,
    output wire         ice_st_spi_d_ready_rev4bodge,
    
    // LED port
    output reg[3:0]     ice_led = 0
);
    // ====================
    // Producer Clock (102 MHz)
    // ====================
    localparam Prod_Clk_Freq = 102_000_000;
    wire prod_clk;
    ClockGen #(
        .FREQOUT(Prod_Clk_Freq),
        .DIVR(0),
        .DIVF(50),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_prod_clk(.clkRef(ice_img_clk16mhz), .clk(prod_clk));
    
    // ====================
    // AFIFOChain
    // ====================
    localparam AFIFOChainCount = 8; // 4096*8=32768 bits=4096 bytes total, readable in chunks of 2048
    
    wire        fifo_rst_           = 1;
    wire        fifo_prop_clk       = prod_clk;
    wire        fifo_prop_w_ready;
    wire        fifo_prop_r_ready;
    wire        fifo_w_clk          = prod_clk;
    reg         fifo_w_trigger      = 0;
    reg[7:0]    fifo_w_data         = 0;
    wire        fifo_w_ready;
    wire        fifo_r_clk          = ice_st_spi_clk;
    reg         fifo_r_trigger      = 0;
    wire[7:0]   fifo_r_data;
    wire        fifo_r_ready;
    
    AFIFOChain #(
        .W(8),
        .N(AFIFOChainCount)
    ) AFIFOChain(
        .rst_(fifo_rst_),
        
        .prop_clk(fifo_prop_clk),
        .prop_w_ready(fifo_prop_w_ready),
        .prop_r_ready(fifo_prop_r_ready),
        
        .w_clk(fifo_w_clk),
        .w_trigger(fifo_w_trigger),
        .w_data(fifo_w_data),
        .w_ready(fifo_w_ready),
        
        .r_clk(fifo_r_clk),
        .r_trigger(fifo_r_trigger),
        .r_data(fifo_r_data),
        .r_ready(fifo_r_ready)
    );
    
    // ====================
    // Producer
    // ====================
    reg[1:0] prod_state = 0;
    reg[10:0] prod_counter = 0;
    
    reg spi_prodTrigger = 0;
    `TogglePulse(prod_trigger, spi_prodTrigger, posedge, prod_clk);
    
    always @(posedge prod_clk) begin
        fifo_w_trigger <= 0;
        fifo_w_data <= fifo_w_data+1;
        prod_counter <= prod_counter+1;
        
        if (fifo_w_trigger) begin
            if (fifo_w_ready) begin
                // $display("Wrote word: 0x%x", fifo_w_data);
            
            // Handle dropped writes
            end else begin
                $display("Error: !fifo_w_ready while writing...");
                `Finish;
            end
        end
        
        case (prod_state)
        0: begin
        end
        
        1: begin
            if (fifo_prop_w_ready) begin
                prod_state <= 2;
            end
        end
        
        2: begin
            fifo_w_trigger <= 1;
            fifo_w_data <= 0;
            prod_counter <= 1;
            prod_state <= 3;
        end
        
        3: begin
            fifo_w_trigger <= 1;
            if (&prod_counter) begin
                prod_state <= 1;
            end
        end
        endcase
        
        if (prod_trigger) prod_state <= 1;
    end
    
    
    // ====================
    // SPI State Machine
    // ====================
    
    // MsgCycleCount notes:
    //
    //   - We include a dummy byte at the beginning of each command, to workaround an
    //     apparent STM32 bug that always sends the first nibble as 0xF. As such, we
    //     need to add 2 cycles to `MsgCycleCount`. Without this dummy byte,
    //     MsgCycleCount=(`Msg_Len/4)-1, so with this dummy byte,
    //     MsgCycleCount=(`Msg_Len/4)+1.
    //
    //   - Commands use 4 lines (ice_st_ice_st_spi_d[3:0]), so we divide `Msg_Len by 4.
    //     Commands use only 4 lines, instead of all 8 lines used for responses,
    //     because dual-QSPI doesn't allow that, since dual-QSPI is meant to control
    //     two separate flash devices, so it outputs the same data on ice_st_ice_st_spi_d[3:0]
    //     that it does on ice_st_ice_st_spi_d[7:4].
    localparam MsgCycleCount = (`Msg_Len/4)+1;
    reg[`RegWidth(MsgCycleCount)-1:0] spi_dinCounter = 0;
    reg[0:0] spi_doutCounter = 0;
    reg[`Msg_Len-1:0] spi_dinReg = 0;
    reg[15:0] spi_doutReg = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    // spi_msgTypeRaw / spi_msgType: STM32's QSPI messaging mechanism doesn't allow
    // for setting the first bit to 1, so we fake the first bit.
    wire[`Msg_Type_Len-1:0] spi_msgTypeRaw = spi_dinReg[`Msg_Type_Bits];
    wire[`Msg_Type_Len-1:0] spi_msgType = {1'b1, spi_msgTypeRaw[`Msg_Type_Len-2:0]};
    wire spi_msgResp = spi_msgType[`Msg_Type_Resp_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_dinReg[`Msg_Arg_Bits];
    
    localparam SDReadoutLen = ((AFIFOChainCount/2)*4096)/8;
    localparam SDReadoutCount = SDReadoutLen+3;
    reg[15:0] spi_sdReadoutWord = 0;
    reg[`RegWidth(SDReadoutCount)-1:0] spi_sdReadoutCounter = 0;
    reg spi_sdReadoutEnding = 0;
    
    wire spi_cs;
    reg spi_d_outEn = 0;
    wire[7:0] spi_d_out;
    wire[7:0] spi_d_in;
    
    assign spi_d_out = {
        `LeftBits(spi_doutReg, 8, 4),   // High 4 bits: 4 bits of byte 1
        `LeftBits(spi_doutReg, 0, 4)    // Low 4 bits:  4 bits of byte 0
    };
    
    localparam SPI_State_MsgIn      = 0;    // +2
    localparam SPI_State_RespOut    = 3;    // +0
    localparam SPI_State_SDReadout  = 4;    // +3
    localparam SPI_State_Nop        = 8;    // +0
    localparam SPI_State_Count      = 9;
    reg[`RegWidth(SPI_State_Count-1)-1:0] spi_state = 0;
    
    always @(posedge ice_st_spi_clk, negedge spi_cs) begin
        // Reset ourself when we're de-selected
        if (!spi_cs) begin
            spi_state <= SPI_State_MsgIn;
            spi_d_outEn <= 0;
            fifo_r_trigger <= 0;
        
        end else begin
            // Commands only use 4 lines (ice_st_spi_d[3:0]) because it's quadspi.
            // See MsgCycleCount comment above.
            spi_dinReg <= spi_dinReg<<4|spi_d_in[3:0];
            spi_dinCounter <= spi_dinCounter-1;
            spi_sdReadoutWord <= spi_sdReadoutWord<<8;
            spi_doutCounter <= spi_doutCounter-1;
            spi_d_outEn <= 0;
            spi_resp <= spi_resp<<8|8'b0;
            fifo_r_trigger <= 0;
            spi_sdReadoutCounter <= spi_sdReadoutCounter-1;
            if (spi_sdReadoutCounter === 4) spi_sdReadoutEnding <= 1;
            spi_doutReg <= spi_doutReg<<4;
            
            case (spi_state)
            SPI_State_MsgIn: begin
                // Verify that we never get a clock while spi_d_in is undriven (z) / invalid (x)
                if ((ice_st_spi_d[0]!==1'b0 && ice_st_spi_d[0]!==1'b1) ||
                    (ice_st_spi_d[1]!==1'b0 && ice_st_spi_d[1]!==1'b1) ||
                    (ice_st_spi_d[2]!==1'b0 && ice_st_spi_d[2]!==1'b1) ||
                    (ice_st_spi_d[3]!==1'b0 && ice_st_spi_d[3]!==1'b1)) begin
                    $display("ice_st_spi_d invalid: %b (time: %0d, spi_cs: %b) ❌", ice_st_spi_d, $time, spi_cs);
                    #1000;
                    `Finish;
                end
                
                spi_dinCounter <= MsgCycleCount;
                spi_state <= SPI_State_MsgIn+1;
            end
            
            SPI_State_MsgIn+1: begin
                if (!spi_dinCounter) begin
                    spi_state <= SPI_State_MsgIn+2;
                end
            end
            
            SPI_State_MsgIn+2: begin
                spi_state <= (spi_msgResp ? SPI_State_RespOut : SPI_State_Nop);
                spi_doutCounter <= 0;
                
                case (spi_msgType)
                `Msg_Type_Echo: begin
                    $display("[SPI] Got Msg_Type_Echo: %0h", spi_msgArg[`Msg_Arg_Echo_Msg_Bits]);
                    spi_resp[`Resp_Arg_Echo_Msg_Bits] <= spi_msgArg[`Msg_Arg_Echo_Msg_Bits];
                end
                
                // LEDSet
                `Msg_Type_LEDSet: begin
                    $display("[SPI] Got Msg_Type_LEDSet: %b", spi_msgArg[`Msg_Arg_LEDSet_Val_Bits]);
                    ice_led <= spi_msgArg[`Msg_Arg_LEDSet_Val_Bits];
                end
                
                `Msg_Type_SDReadout: begin
                    $display("[SPI] Got Msg_Type_SDReadout");
                    spi_prodTrigger <= 1; // Only triggers once (once started, the producer continues forever)
                    spi_state <= SPI_State_SDReadout;
                end
                
                `Msg_Type_Nop: begin
                    $display("[SPI] Got Msg_Type_Nop");
                end
                
                default: begin
                    $display("[SPI] BAD COMMAND: %0d ❌", spi_msgType);
                    `Finish;
                end
                endcase
            end
            
            SPI_State_RespOut: begin
                spi_d_outEn <= 1;
                if (!spi_doutCounter) begin
                    spi_doutReg <= `LeftBits(spi_resp, 0, 16);
                end
            end
            
            SPI_State_SDReadout: begin
                // Delay state
                spi_state <= SPI_State_SDReadout+1;
            end
            
            SPI_State_SDReadout+1: begin
                spi_sdReadoutCounter <= 2;
                spi_state <= SPI_State_SDReadout+2;
            end
            
            SPI_State_SDReadout+2: begin
                spi_doutCounter <= 1;
                if (!spi_sdReadoutCounter) begin
                    spi_sdReadoutCounter <= SDReadoutCount;
                    spi_sdReadoutEnding <= 0;
                    spi_state <= SPI_State_SDReadout+3;
                end
            end
            
            SPI_State_SDReadout+3: begin
                spi_d_outEn <= 1;
                spi_sdReadoutWord[7:0] <= fifo_r_data;
                fifo_r_trigger <= !spi_sdReadoutEnding;
                
                if (!spi_doutCounter) begin
                    spi_doutReg <= spi_sdReadoutWord;
                end
                
                if (!spi_sdReadoutCounter) begin
                    spi_state <= SPI_State_SDReadout+1;
                end
            end
            
            SPI_State_Nop: begin
            end
            endcase
        end
    end
    
    // ====================
    // Pin: ice_st_spi_cs_
    // ====================
    wire spi_cs_tmp_;
    SB_IO #(
        .PIN_TYPE(6'b0000_01),
        .PULLUP(1'b1)
    ) SB_IO_ice_st_spi_cs_ (
        .PACKAGE_PIN(ice_st_spi_cs_),
        .D_IN_0(spi_cs_tmp_)
    );
    assign spi_cs = !spi_cs_tmp_;
    
    // ====================
    // Pin: ice_st_spi_d
    // ====================
    genvar i;
    for (i=0; i<8; i++) begin
        SB_IO #(
            .PIN_TYPE(6'b1001_00)
        ) SB_IO_ice_st_spi_d (
            .INPUT_CLK(ice_st_spi_clk),
            .OUTPUT_CLK(ice_st_spi_clk),
            .PACKAGE_PIN(ice_st_spi_d[i]),
            .OUTPUT_ENABLE(spi_d_outEn),
            .D_OUT_0(spi_d_out[i]),
            .D_IN_0(spi_d_in[i])
        );
    end
    
    // ====================
    // Pin: ice_st_spi_d_ready
    // ====================
    assign ice_st_spi_d_ready = fifo_prop_r_ready;
    // Rev4 bodge
    assign ice_st_spi_d_ready_rev4bodge = ice_st_spi_d_ready;
    
endmodule
