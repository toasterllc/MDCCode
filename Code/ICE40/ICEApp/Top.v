`include "Util.v"
`include "Sync.v"
`include "ICEAppTypes.v"

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    input wire          ice_msp_spi_clk,
    inout wire          ice_msp_spi_data,
    
`ifdef SIM
    output wire         sim_rst_,
`endif
    
    output reg[3:0]     ice_led = 0
);
    wire spi_clk = ice_msp_spi_clk;
    reg spi_dataOut = 0;
    reg spi_dataOutEn = 0;
    wire spi_dataIn;
    
    // ====================
    // Pin: ice_msp_spi_data
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00),
        .PULLUP(1'b1)
    ) SB_IO_ice_msp_spi_data (
        .INPUT_CLK(ice_msp_spi_clk),
        .OUTPUT_CLK(ice_msp_spi_clk),
        .PACKAGE_PIN(ice_msp_spi_data),
        .OUTPUT_ENABLE(spi_dataOutEn),
        .D_OUT_0(spi_dataOut),
        .D_IN_0(spi_dataIn)
    );
    
    
    
    
    
    // ====================
    // spi_rst_ Generation
    // ====================
    localparam SPIRstClkFreqHz = 16000000;
    // Our math is such that asserting `spi_clk` for 2x `SPIRstActivateThresholdUs`
    // is guaranteed to trigger a reset.
    // This is because we size `spirst_counter` to fit `SPIRstActivateThresholdUs`,
    // but `spi_rst_` is only asserted when all bits in `spirst_counter` are 1,
    // which will likely be >SPIRstTicks, since SPIRstTicks likely isn't a power
    // of 2.
    localparam SPIRstActivateThresholdUs = 5;
    localparam SPIRstTicks = (SPIRstClkFreqHz*SPIRstActivateThresholdUs)/1000000;
    wire spirst_clk = ice_img_clk16mhz;
    reg[`RegWidth(SPIRstTicks-1)-1:0] spirst_counter = 0;
    `Sync(spirst_spiClkSynced, spi_clk, posedge, spirst_clk);
    wire spi_rst_ = !(&spirst_counter);
    always @(posedge spirst_clk) begin
        spirst_counter <= spirst_counter;
        if (!spirst_spiClkSynced) begin
            spirst_counter <= 0;
        end else if (spi_rst_) begin
            spirst_counter <= spirst_counter+1;
        end
    end
`ifdef SIM
    assign sim_rst_ = spi_rst_;
`endif
    
    // ====================
    // SPI State Machine
    // ====================
    localparam TurnaroundDelay = 8;
    localparam TurnaroundInherentDelay = 4;
    localparam TurnaroundExtraDelay = TurnaroundDelay-TurnaroundInherentDelay;
    localparam MsgCycleCount = `Msg_Len+TurnaroundExtraDelay-2;
    localparam RespCycleCount = `Resp_Len-1;
    
    reg[`Msg_Len-1:0] spi_dataInReg = 0;
    wire[`Msg_Type_Len-1:0] spi_msgType = spi_dataInReg[`Msg_Type_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_dataInReg[`Msg_Arg_Bits];
    reg[`RegWidth2(MsgCycleCount,RespCycleCount)-1:0] spi_dataCounter = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    reg[TurnaroundExtraDelay-1:0] spi_dataInDelayed = 0;
    
    localparam SPI_State_MsgIn      = 0;    // +2
    localparam SPI_State_RespOut    = 3;    // +0
    localparam SPI_State_Count      = 4;
    reg[`RegWidth(SPI_State_Count-1)-1:0] spi_state = 0;
    
    always @(posedge spi_clk, negedge spi_rst_) begin
        if (!spi_rst_) begin
            $display("[SPI] Reset");
            spi_state <= 0;
            spi_dataOutEn <= 0;
        
        end else begin
            spi_dataInDelayed <= spi_dataInDelayed<<1|spi_dataIn;
            spi_dataInReg <= spi_dataInReg<<1|`LeftBit(spi_dataInDelayed,0);
            spi_dataCounter <= spi_dataCounter-1;
            spi_dataOutEn <= 0;
            spi_resp <= spi_resp<<1|1'b1;
            spi_dataOut <= `LeftBit(spi_resp, 0);
            
            case (spi_state)
            SPI_State_MsgIn: begin
                // Wait for the start of the message, signified by the first 0 bit
                if (!spi_dataIn) begin
                    spi_dataCounter <= MsgCycleCount;
                    spi_state <= SPI_State_MsgIn+1;
                end
            end
        
            SPI_State_MsgIn+1: begin
                if (!spi_dataCounter) begin
                    spi_state <= SPI_State_MsgIn+2;
                end
            end
        
            SPI_State_MsgIn+2: begin
                // By default, go to SPI_State_Nop
                spi_state <= SPI_State_RespOut;
                spi_dataCounter <= RespCycleCount;
            
                case (spi_msgType)
                // Echo
                `Msg_Type_Echo: begin
                    $display("[SPI] Got Msg_Type_Echo: %0h", spi_msgArg[`Msg_Arg_Echo_Msg_Bits]);
                    // spi_resp <= 64'hxxxxxxxx_xxxxxxxx;
                    // spi_resp <= 64'h12345678_ABCDEF12;
                    spi_resp[`Resp_Arg_Echo_Msg_Bits] <= spi_msgArg[`Msg_Arg_Echo_Msg_Bits];
                end
            
                // LEDSet
                `Msg_Type_LEDSet: begin
                    $display("[SPI] Got Msg_Type_LEDSet: %b", spi_msgArg[`Msg_Arg_LEDSet_Val_Bits]);
                    ice_led <= spi_msgArg[`Msg_Arg_LEDSet_Val_Bits];
                end
            
                `Msg_Type_NoOp: begin
                    $display("[SPI] Got Msg_Type_None");
                end
            
                default: begin
                    $display("[SPI] BAD COMMAND: %0d ❌", spi_msgType);
                    `Finish;
                end
                endcase
            end
        
            SPI_State_RespOut: begin
                spi_dataOutEn <= 1;
                if (!spi_dataCounter) begin
                    spi_state <= SPI_State_MsgIn;
                end
            end
            endcase
        end
    end
endmodule







`ifdef SIM
module Testbench();
    reg ice_img_clk16mhz = 0;
    reg ice_msp_spi_clk = 0;
    wire ice_msp_spi_data;
    wire[3:0] ice_led;
    wire sim_rst_;
    
    initial begin
        forever begin
            ice_img_clk16mhz = 0;
            #32;
            ice_img_clk16mhz = 1;
            #32;
        end
    end
    
    Top Top(.*);
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    reg[`Msg_Len-1:0] spi_dataOutReg = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    
    reg spi_dataOutEn = 0;    
    wire spi_dataIn = ice_msp_spi_data;
    assign ice_msp_spi_data = (spi_dataOutEn ? `LeftBit(spi_dataOutReg, 0) : 1'bz);
    
    // localparam ice_msp_spi_clk_HALF_PERIOD = 32; // 16 MHz
    localparam ice_msp_spi_clk_HALF_PERIOD = 1024; // 1 MHz
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg, input[31:0] respLen); begin
        reg[15:0] i;
        
        spi_dataOutReg = {typ, arg};
        spi_dataOutEn = 1;
        
        for (i=0; i<`Msg_Len; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
            
            spi_dataOutReg = spi_dataOutReg<<1|1'b1;
        end
        
        spi_dataOutEn = 0;
        
        // Turnaround delay cycles
        for (i=0; i<8; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
        end
        
        // Clock in response
        for (i=0; i<respLen; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            
                spi_resp = spi_resp<<1|spi_dataIn;
            
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
        end
    end endtask
    
    task TestRst; begin
        $display("\n========== TestRst ==========");
        
        $display("\nice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #10000;
        
        if (sim_rst_ === 1'b1) begin
            $display("sim_rst_ === 1'b1 ✅");
        end else begin
            $display("sim_rst_ !== 1'b1 ❌");
            `Finish;
        end
        
        $display("\nice_msp_spi_clk = 1");
        ice_msp_spi_clk = 1;
        #10000;
        
        if (sim_rst_ === 1'b0) begin
            $display("sim_rst_ === 1'b0 ✅");
        end else begin
            $display("sim_rst_ !== 1'b0 ❌");
            `Finish;
        end
        
        $display("\nice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #10000;
        
        if (sim_rst_ === 1'b1) begin
            $display("sim_rst_ === 1'b1 ✅");
        end else begin
            $display("sim_rst_ !== 1'b1 ❌");
            `Finish;
        end
        
    end endtask
    
    task TestNoOp; begin
        $display("\n========== TestNoOp ==========");
        SendMsg(`Msg_Type_NoOp, 56'hFFFFFFFFFFFFFF, `Resp_Len);
        if (spi_resp === 64'hxxxxxxxxxxxxxxxx) begin
            $display("Response OK: %h ✅", spi_resp);
        end else begin
            $display("Bad response: %h ❌", spi_resp);
            `Finish;
        end
    end endtask
    
    task TestEcho(input[`Msg_Arg_Echo_Msg_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n========== TestEcho ==========");
        arg[`Msg_Arg_Echo_Msg_Bits] = val;
        
        SendMsg(`Msg_Type_Echo, arg, `Resp_Len);
        if (spi_resp[`Resp_Arg_Echo_Msg_Bits] === val) begin
            $display("Response OK: %h ✅", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
        end else begin
            $display("Bad response: %h ❌", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
            `Finish;
        end
    end endtask
    
    task TestLEDSet(input[`Msg_Arg_LEDSet_Val_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n========== TestLEDSet ==========");
        arg[`Msg_Arg_LEDSet_Val_Bits] = val;
        
        SendMsg(`Msg_Type_LEDSet, arg, `Resp_Len);
        if (ice_led === val) begin
            $display("ice_led matches (%b) ✅", ice_led);
        end else begin
            $display("ice_led doesn't match (expected: %b, got: %b) ❌", val, ice_led);
            `Finish;
        end
    end endtask
    
    initial begin
        // Set our initial state
        spi_dataOutReg = ~0;
        spi_dataOutEn = 0;
        
        // Pulse the clock to get SB_IO initialized
        ice_msp_spi_clk = 1;
        #1;
        ice_msp_spi_clk = 0;
        
        TestRst();
        TestNoOp();
        TestEcho(56'hCAFEBABEFEEDAA);
        TestLEDSet(4'b1010);
        TestLEDSet(4'b0101);
        TestEcho(56'h123456789ABCDE);
        TestNoOp();
        TestRst();
        
        `Finish;
    end
endmodule
`endif
