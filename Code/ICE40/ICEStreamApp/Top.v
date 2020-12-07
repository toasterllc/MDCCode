// TODO: investigate whether our various toggle signals that cross clock domains are safe (such as sd_ctrl_cmdTrigger).
// currently we syncronize the toggled signal across clock domains, and assume that all dependent signals
// (sd_ctrl_cmdRespType_48, sd_ctrl_cmdRespType_136) have settled by the time the toggled signal lands in the destination
// clock domain. but if the destination clock is fast enough relative to the source clock, couldn't the destination
// clock observe the toggled signal before the dependent signals have settled?
// we should probably delay the toggle signal by 1 cycle in the source clock domain, to guarantee that all the
// dependent signals have settled in the source clock domain.

`include "Sync.v"
`include "TogglePulse.v"
`include "ToggleAck.v"
`include "ClockGen.v"
`include "PixController.v"
`include "PixI2CMaster.v"
`include "RAMController.v"
`include "ICEAppTypes.v"

`ifdef SIM
`include "PixSim.v"
`include "PixI2CSlaveSim.v"
`include "../../mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    
    input wire          spi_clk,
    input wire          spi_cs_,
    inout wire[7:0]     spi_d,
    
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    output reg          pix_rst_ = 0,
    output wire         pix_sclk,
    inout wire          pix_sdata,
    
    // RAM port
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
    
    // output reg[3:0]     led = 0
);
    // ====================
    // PixI2CMaster
    // ====================
    localparam PixI2CSlaveAddr = 7'h10;
    reg pixi2c_cmd_write = 0;
    reg[15:0] pixi2c_cmd_regAddr = 0;
    reg pixi2c_cmd_dataLen = 0;
    reg[15:0] pixi2c_cmd_writeData = 0;
    reg pixi2c_cmd_trigger = 0;
    wire pixi2c_status_done;
    wire pixi2c_status_err;
    wire[15:0] pixi2c_status_readData;
    `ToggleAck(spi_pixi2c_done_, spi_pixi2c_doneAck, pixi2c_status_done, posedge, spi_clk);
    
    PixI2CMaster #(
        .ClkFreq(24_000_000),
`ifdef SIM
        .I2CClkFreq(4_000_000)
`else
        .I2CClkFreq(100_000) // TODO: try 400_000 (the max frequency) to see if it works. if not, the pullup's likely too weak.
`endif
    ) PixI2CMaster (
        .clk(clk24mhz),
        
        .cmd_slaveAddr(PixI2CSlaveAddr),
        .cmd_write(pixi2c_cmd_write),
        .cmd_regAddr(pixi2c_cmd_regAddr),
        .cmd_dataLen(pixi2c_cmd_dataLen),
        .cmd_writeData(pixi2c_cmd_writeData),
        .cmd_trigger(pixi2c_cmd_trigger), // Toggle
        
        .status_done(pixi2c_status_done), // Toggle
        .status_err(pixi2c_status_err),
        .status_readData(pixi2c_status_readData),
        
        .i2c_clk(pix_sclk),
        .i2c_data(pix_sdata)
    );
    
    
    
    
    
    
    
    // ====================
    // Pix Clock (108 MHz)
    // ====================
    localparam Pix_Clk_Freq = 108_000_000;
    wire pix_clk;
    ClockGen #(
        .FREQ(Pix_Clk_Freq),
        .DIVR(0),
        .DIVF(35),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_pix_clk(.clkRef(clk24mhz), .clk(pix_clk));
    
    // ====================
    // PixController
    // ====================
    reg[1:0]    pixctrl_cmd = 0;
    reg[2:0]    pixctrl_cmd_ramBlock = 0;
    wire        pixctrl_readout_clk;
    wire        pixctrl_readout_ready;
    wire        pixctrl_readout_trigger;
    wire[15:0]  pixctrl_readout_data;
    wire        pixctrl_status_captureDone;
    wire        pixctrl_status_capturePixelDropped;
    wire        pixctrl_status_readoutStarted;
    PixController #(
        .ClkFreq(Pix_Clk_Freq),
        .ImageSize(ImageWidth*ImageHeight)
    ) PixController (
        .clk(pix_clk),
        
        .cmd(pixctrl_cmd),
        .cmd_ramBlock(pixctrl_cmd_ramBlock),
        
        .readout_clk(pixctrl_readout_clk),
        .readout_ready(pixctrl_readout_ready),
        .readout_trigger(pixctrl_readout_trigger),
        .readout_data(pixctrl_readout_data),
        
        .status_captureDone(pixctrl_status_captureDone),
        .status_capturePixelDropped(pixctrl_status_capturePixelDropped),
        .status_readoutStarted(pixctrl_status_readoutStarted),
        
        .pix_dclk(pix_dclk),
        .pix_d(pix_d),
        .pix_fv(pix_fv),
        .pix_lv(pix_lv),
        
        .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq)
    );
    
    reg spi_pixCaptureTrigger = 0;
    `TogglePulse(pix_captureTrigger, spi_pixCaptureTrigger, posedge, pix_clk);
    reg pix_pixctrlReadoutReadyPrev = 0;
    `Sync(pix_pixctrlReadoutReady, pixctrl_readout_ready, posedge, pix_clk);
    reg pix_readoutStarted = 0;
    
    localparam Pix_State_Idle       = 0;    // +0
    localparam Pix_State_Capture    = 1;    // +1
    localparam Pix_State_Readout    = 3;    // +1
    localparam Pix_State_Count      = 5;
    reg[`RegWidth(Pix_State_Count-1)-1:0] pix_state = 0;
    always @(posedge pix_clk) begin
        pixctrl_cmd <= `PixController_Cmd_None;
        pix_pixctrlReadoutReadyPrev <= pix_pixctrlReadoutReady;
        
        case (pix_state)
        Pix_State_Idle: begin
        end
        
        Pix_State_Capture: begin
            // Start a capture
            pixctrl_cmd <= `PixController_Cmd_Capture;
            pix_state <= Pix_State_Capture+1;
        end
        
        Pix_State_Capture+1: begin
            // Wait for the capture to complete, and then start readout
            if (pixctrl_status_captureDone) begin
                pixctrl_cmd <= `PixController_Cmd_Readout;
                pix_state <= Pix_State_Readout;
            end
        end
        
        Pix_State_Readout: begin
            // Wait for readout to start, and then signal so via pix_readoutStarted
            if (pixctrl_status_readoutStarted) begin
                pix_readoutStarted <= !pix_readoutStarted;
                pix_state <= Pix_State_Readout+1;
            end
        end
        
        Pix_State_Readout+1: begin
            // Wait for readout to complete, and then start a new capture
            if (pix_pixctrlReadoutReadyPrev && !pix_pixctrlReadoutReady) begin
                pix_state <= Pix_State_Capture;
            end
        end
        endcase
        
        if (pix_captureTrigger) begin
            // led <= 4'b1111;
            pix_state <= Pix_State_Capture;
        end
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
    //   - Commands use 4 lines (spi_d[3:0]), so we divide `Msg_Len by 4.
    //
    localparam MsgCycleCount = (`Msg_Len/4)+1;
    reg[`RegWidth(MsgCycleCount)-1:0] spi_dinCounter = 0;
    reg[0:0] spi_doutCounter = 0;
    reg[`Msg_Len-1:0] spi_dinReg = 0;
    reg[15:0] spi_doutReg = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    wire[`Msg_Type_Len-1:0] spi_msgType = spi_dinReg[`Msg_Type_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_dinReg[`Msg_Arg_Bits];
    reg[`Msg_Arg_PixReadout_Counter_Len-1:0] spi_pixReadoutCounter = 0;
    reg spi_pixReadoutDone = 0;
    
    wire spi_cs;
    reg spi_d_outEn = 0;
    wire[7:0] spi_d_out;
    wire[7:0] spi_d_in;
    
    assign spi_d_out = {
        `LeftBits(spi_doutReg, 8, 4),   // High 4 bits: 4 bits of byte 1
        `LeftBits(spi_doutReg, 0, 4)    // Low 4 bits:  4 bits of byte 0
    };
    
    `Sync(spi_pixctrlStatusCapturePixelDropped, pixctrl_status_capturePixelDropped, posedge, spi_clk);
    `ToggleAck(spi_pixReadoutStarted, spi_pixReadoutStartedAck, pix_readoutStarted, posedge, spi_clk);
    
    assign pixctrl_readout_clk = spi_clk;
    wire spi_pixctrlReadoutReady = pixctrl_readout_ready;
    reg spi_pixctrlReadoutTrigger = 0;
    assign pixctrl_readout_trigger = spi_pixctrlReadoutTrigger;
    wire[15:0] spi_pixctrlReadoutData = pixctrl_readout_data;
    // `spi_pixReadoutReady` combines the state of (1) readout having started, and (2) data being available in the FIFO.
    // This is so that a new PixCapture message that interrupts a readout will force `spi_pixReadoutReady`=0,
    // because `spi_pixReadoutStarted`=0 until the new capture is complete and readout starts.
    wire spi_pixReadoutReady = spi_pixReadoutStarted && spi_pixctrlReadoutReady;
    
    localparam SPI_State_MsgIn      = 0;    // +2
    localparam SPI_State_RespOut    = 3;    // +0
    localparam SPI_State_PixOut     = 4;    // +0
    localparam SPI_State_Nop        = 5;    // +0
    localparam SPI_State_Count      = 6;
    reg[`RegWidth(SPI_State_Count-1)-1:0] spi_state = 0;
    
    always @(posedge spi_clk, negedge spi_cs) begin
        // Reset ourself when we're de-selected
        if (!spi_cs) begin
            spi_state <= 0;
            spi_d_outEn <= 0;
        
        end else begin
            // Commands only use 4 lines (spi_d[3:0]) because it's quadspi.
            spi_dinReg <= spi_dinReg<<4|spi_d_in[3:0];
            spi_dinCounter <= spi_dinCounter-1;
            spi_doutReg <= spi_doutReg<<4|4'hF;
            spi_doutCounter <= spi_doutCounter-1;
            spi_d_outEn <= 0;
            spi_resp <= spi_resp<<8|8'hFF;
            
            spi_pixReadoutCounter <= spi_pixReadoutCounter-1;
            if (!spi_pixReadoutCounter) spi_pixReadoutDone <= 1;
            spi_pixctrlReadoutTrigger <= 0;
            
            case (spi_state)
            SPI_State_MsgIn: begin
                spi_dinCounter <= MsgCycleCount;
                spi_state <= 1;
            end
            
            SPI_State_MsgIn+1: begin
                if (!spi_dinCounter) begin
                    spi_state <= 2;
                end
            end
            
            SPI_State_MsgIn+2: begin
                // By default, go to SPI_State_Nop
                spi_state <= SPI_State_Nop;
                spi_doutCounter <= 0;
                
                case (spi_msgType)
                // Echo
                `Msg_Type_Echo: begin
                    $display("[SPI] Got Msg_Type_Echo: %0h", spi_msgArg[`Msg_Arg_Echo_Msg_Bits]);
                    spi_resp[`Resp_Arg_Echo_Msg_Bits] <= spi_msgArg[`Msg_Arg_Echo_Msg_Bits];
                    spi_state <= SPI_State_RespOut;
                end
                
                `Msg_Type_PixReset: begin
                    $display("[SPI] Got Msg_Type_PixReset (rst=%b)", spi_msgArg[`Msg_Arg_PixReset_Val_Bits]);
                    pix_rst_ <= spi_msgArg[`Msg_Arg_PixReset_Val_Bits];
                end
                
                `Msg_Type_PixCapture: begin
                    $display("[SPI] Got Msg_Type_PixCapture (block=%b)", spi_msgArg[`Msg_Arg_PixCapture_DstBlock_Bits]);
                    pixctrl_cmd_ramBlock <= spi_msgArg[`Msg_Arg_PixCapture_DstBlock_Bits];
                    spi_pixCaptureTrigger <= !spi_pixCaptureTrigger;
                end
                
                `Msg_Type_PixReadout: begin
                    $display("[SPI] Got Msg_Type_PixReadout");
                    // Reset `spi_pixReadoutStarted` if it's asserted
                    if (spi_pixReadoutStarted) spi_pixReadoutStartedAck <= !spi_pixReadoutStartedAck;
                    
                    spi_pixReadoutCounter <= spi_msgArg[`Msg_Arg_PixReadout_Counter_Bits];
                    spi_pixReadoutDone <= 0;
                    spi_state <= SPI_State_PixOut;
                end
                
                `Msg_Type_PixI2CTransaction: begin
                    $display("[SPI] Got Msg_Type_PixI2CTransaction");
                    
                    // Reset `spi_pixi2c_done_` if it's asserted
                    if (!spi_pixi2c_done_) spi_pixi2c_doneAck <= !spi_pixi2c_doneAck;
                    
                    pixi2c_cmd_write <= spi_msgArg[`Msg_Arg_PixI2CTransaction_Write_Bits];
                    pixi2c_cmd_regAddr <= spi_msgArg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits];
                    pixi2c_cmd_dataLen <= (spi_msgArg[`Msg_Arg_PixI2CTransaction_DataLen_Bits]===`Msg_Arg_PixI2CTransaction_DataLen_2);
                    pixi2c_cmd_writeData <= spi_msgArg[`Msg_Arg_PixI2CTransaction_WriteData_Bits];
                    pixi2c_cmd_trigger <= !pixi2c_cmd_trigger;
                end
                
                `Msg_Type_PixGetStatus: begin
                    // $display("[SPI] Got Msg_Type_PixGetStatus [I2CDone:%b, I2CErr:%b, I2CReadData:%b ReadoutReady:%b]",
                    //     !spi_pixi2c_done_,
                    //     pixi2c_status_err,
                    //     pixi2c_status_readData,
                    //     spi_pixReadoutReady
                    // );
                    spi_resp[`Resp_Arg_PixGetStatus_I2CDone_Bits] <= !spi_pixi2c_done_;
                    spi_resp[`Resp_Arg_PixGetStatus_I2CErr_Bits] <= pixi2c_status_err;
                    spi_resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits] <= pixi2c_status_readData;
                    spi_resp[`Resp_Arg_PixGetStatus_ReadoutReady_Bits] <= spi_pixReadoutReady;
                    spi_state <= SPI_State_RespOut;
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
                spi_d_outEn <= 1;
                if (!spi_doutCounter) begin
                    spi_doutReg <= `LeftBits(spi_resp, 0, 16);
                end
            end
            
            SPI_State_PixOut: begin
                spi_d_outEn <= 1;
                if (!spi_doutCounter) begin
                    spi_doutReg <= spi_pixctrlReadoutData;
                    spi_pixctrlReadoutTrigger <= 1;
                end
                
                if (spi_pixReadoutDone) begin
                    spi_state <= SPI_State_Nop;
                end
            end
            
            SPI_State_Nop: begin
            end
            endcase
        end
    end
    
    // ====================
    // Pin: spi_cs_
    // ====================
    wire spi_cs_tmp_;
    SB_IO #(
        .PIN_TYPE(6'b0000_01),
        .PULLUP(1'b1)
    ) SB_IO_spi_cs (
        .PACKAGE_PIN(spi_cs_),
        .D_IN_0(spi_cs_tmp_)
    );
    assign spi_cs = !spi_cs_tmp_;
    
    // ====================
    // Pin: spi_d
    // ====================
    genvar i;
    for (i=0; i<8; i++) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_00),
            .PULLUP(1'b1)
        ) SB_IO_sd_cmd (
            .INPUT_CLK(spi_clk),
            .OUTPUT_CLK(spi_clk),
            .PACKAGE_PIN(spi_d[i]),
            .OUTPUT_ENABLE(spi_d_outEn),
            .D_OUT_0(spi_d_out[i]),
            .D_IN_0(spi_d_in[i])
        );
    end
endmodule







`ifdef SIM
module Testbench();
    reg         clk24mhz = 0;
    
    reg         spi_clk = 0;
    reg         spi_cs_ = 0;
    wire[7:0]   spi_d;
    
    wire        pix_dclk;
    wire[11:0]  pix_d;
    wire        pix_fv;
    wire        pix_lv;
    wire        pix_rst_;
    wire        pix_sclk;
    tri1        pix_sdata;
    
    wire        ram_clk;
    wire        ram_cke;
    wire[1:0]   ram_ba;
    wire[12:0]  ram_a;
    wire        ram_cs_;
    wire        ram_ras_;
    wire        ram_cas_;
    wire        ram_we_;
    wire[1:0]   ram_dqm;
    wire[15:0]  ram_dq;
    
    wire[3:0]   led;
    
    Top Top(.*);
    
    PixSim #(
        .ImageWidth(ImageWidth),
        .ImageHeight(ImageHeight)
    ) PixSim (
        .pix_dclk(pix_dclk),
        .pix_d(pix_d),
        .pix_fv(pix_fv),
        .pix_lv(pix_lv),
        .pix_rst_(pix_rst_)
    );
    
    PixI2CSlaveSim PixI2CSlaveSim(
        .i2c_clk(pix_sclk),
        .i2c_data(pix_sdata)
    );
    
    mobile_sdr mobile_sdr(
        .clk(ram_clk),
        .cke(ram_cke),
        .addr(ram_a),
        .ba(ram_ba),
        .cs_n(ram_cs_),
        .ras_n(ram_ras_),
        .cas_n(ram_cas_),
        .we_n(ram_we_),
        .dq(ram_dq),
        .dqm(ram_dqm)
    );
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        forever begin
            clk24mhz = 0;
            #21;
            clk24mhz = 1;
            #21;
        end
    end
    
    wire[7:0]   spi_d_out;
    reg         spi_d_outEn = 0;    
    wire[7:0]   spi_d_in;
    assign spi_d = (spi_d_outEn ? spi_d_out : {8{1'bz}});
    assign spi_d_in = spi_d;
    
    reg[`Msg_Len-1:0] spi_doutReg = 0;
    reg[15:0] spi_dinReg = 0;
    reg[`Resp_Len-1:0] resp = 0;
    reg[((ImageWidth*2)*8)-1:0] pixRow = 0;
    assign spi_d_out[7:4] = `LeftBits(spi_doutReg,0,4);
    assign spi_d_out[3:0] = `LeftBits(spi_doutReg,0,4);
    
    localparam SPI_CLK_HALF_PERIOD = 21;
    
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg, input[31:0] respLen); begin
        reg[15:0] i;
        
        spi_cs_ = 0;
        spi_doutReg = {typ, arg};
        spi_d_outEn = 1;
            
            // 2 initial dummy cycles
            for (i=0; i<2; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
            end
            
            for (i=0; i<`Msg_Len/4; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
                
                spi_doutReg = spi_doutReg<<4|{4{1'b1}};
            end
            
            spi_d_outEn = 0;
            
            // Dummy cycles
            for (i=0; i<4; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
            end
            
            // Clock in response
            for (i=0; i<respLen; i++) begin
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 1;
                
                    if (!i[0]) spi_dinReg = 0;
                    spi_dinReg = spi_dinReg<<4|{4'b0000, spi_d_in[3:0], 4'b0000, spi_d_in[7:4]};
                    
                    resp = resp<<8;
                    if (i[0]) resp = resp|spi_dinReg;
                
                #(SPI_CLK_HALF_PERIOD);
                spi_clk = 0;
            end
        
        spi_cs_ = 1;
        #1; // Allow spi_cs_ to take effect
    end endtask
    
    task TestNoOp; begin
        $display("\n========== TestNoOp ==========");
        SendMsg(`Msg_Type_NoOp, 56'h123456789ABCDE, 8);
        if (resp === 64'hFFFFFFFFFFFFFFFF) begin
            $display("Response OK: %h ✅", resp);
        end else begin
            $display("Bad response: %h ❌", resp);
            `Finish;
        end
    end endtask
    
    task TestEcho; begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n========== TestEcho ==========");
        arg[`Msg_Arg_Echo_Msg_Bits] = `Msg_Arg_Echo_Msg_Len'h123456789ABCDE;
        
        SendMsg(`Msg_Type_Echo, arg, 8);
        if (resp[`Resp_Arg_Echo_Msg_Bits] === arg) begin
            $display("Response OK: %h ✅", resp[`Resp_Arg_Echo_Msg_Bits]);
        end else begin
            $display("Bad response: %h ❌", resp[`Resp_Arg_Echo_Msg_Bits]);
            `Finish;
        end
    end endtask
    
    task TestPixReset; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n========== TestPixReset ==========");
        
        // ====================
        // Test Pix reset
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixReset_Val_Bits] = 0;
        SendMsg(`Msg_Type_PixReset, arg, 0);
        if (pix_rst_ === arg[`Msg_Arg_PixReset_Val_Bits]) begin
            $display("[STM32] Reset=0 success ✅");
        end else begin
            $display("[STM32] Reset=0 failed ❌");
        end
        
        arg = 0;
        arg[`Msg_Arg_PixReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_PixReset, arg, 0);
        if (pix_rst_ === arg[`Msg_Arg_PixReset_Val_Bits]) begin
            $display("[STM32] Reset=1 success ✅");
        end else begin
            $display("[STM32] Reset=1 failed ❌");
        end
    end endtask

    task TestPixStream; begin
        reg[`Msg_Arg_Len-1:0] arg;
        reg[31:0] row;
        reg[31:0] col;
        reg[31:0] i;
        reg[31:0] transferPixelCount;
        $display("\n========== TestPixStream ==========");
        
        arg = 0;
        arg[`Msg_Arg_PixReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_PixReset, arg, 0); // Deassert Pix reset
        
        arg = 0;
        arg[`Msg_Arg_PixCapture_DstBlock_Bits] = 0;
        SendMsg(`Msg_Type_PixCapture, arg, 0);
        
        forever begin
            // Wait until readout is ready
            $display("[STM32] Waiting until readout is ready...");
            do begin
                // Request Pix status
                SendMsg(`Msg_Type_PixGetStatus, 0, 8);
            end while(!resp[`Resp_Arg_PixGetStatus_ReadoutReady_Bits]);
            $display("[STM32] Readout ready ✅");
        
            // 1 pixels     counter=0
            // 2 pixels     counter=2
            // 3 pixels     counter=4
            // 4 pixels     counter=6
            transferPixelCount = 4; // 4 pixels at a time (since `resp` is only 8 bytes=4 pixels wide)
            for (row=0; row<ImageHeight; row++) begin
                for (i=0; i<ImageWidth/transferPixelCount; i++) begin
                    arg[`Msg_Arg_PixReadout_Counter_Bits] = (transferPixelCount-1)*2;
                    arg[`Msg_Arg_PixReadout_SrcBlock_Bits] = 0;
                
                    SendMsg(`Msg_Type_PixReadout, arg, transferPixelCount*2);
                    pixRow = (pixRow<<(transferPixelCount*2*8))|resp;
                end
            
                $display("Row %04d: %h", row, pixRow);
            end
        end
    end endtask

    task TestPixI2CWriteRead; begin
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;

        // ====================
        // Test PixI2C Write (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 1;
        arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_2;
        arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h4242;
        arg[`Msg_Arg_PixI2CTransaction_WriteData_Bits] = 16'hCAFE;
        SendMsg(`Msg_Type_PixI2CTransaction, arg, 0);

        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_PixGetStatus, 0, 8);
            $display("[STM32] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end

        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[STM32] Write success ✅");
        end else begin
            $display("[STM32] Write failed ❌");
        end

        // ====================
        // Test PixI2C Read (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_2;
        arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h4242;
        SendMsg(`Msg_Type_PixI2CTransaction, arg, 0);

        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_PixGetStatus, 0, 8);
            $display("[STM32] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end

        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[STM32] Read success ✅");
        end else begin
            $display("[STM32] Read failed ❌");
        end

        if (resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits] === 16'hCAFE) begin
            $display("[STM32] Read correct data ✅ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]);
        end else begin
            $display("[STM32] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]);
            `Finish;
        end

        // ====================
        // Test PixI2C Write (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 1;
        arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_1;
        arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h8484;
        arg[`Msg_Arg_PixI2CTransaction_WriteData_Bits] = 16'h0037;
        SendMsg(`Msg_Type_PixI2CTransaction, arg, 0);

        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_PixGetStatus, 0, 8);
            $display("[STM32] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end

        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[STM32] Write success ✅");
        end else begin
            $display("[STM32] Write failed ❌");
        end

        // ====================
        // Test PixI2C Read (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_1;
        arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h8484;
        SendMsg(`Msg_Type_PixI2CTransaction, arg, 0);

        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_PixGetStatus, 0, 8);
            $display("[STM32] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end

        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[STM32] Read success ✅");
        end else begin
            $display("[STM32] Read failed ❌");
        end

        if ((resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF) === 16'h0037) begin
            $display("[STM32] Read correct data ✅ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF);
        end else begin
            $display("[STM32] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF);
        end
    end endtask
    
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        
        // Set our initial state
        spi_cs_ = 1;
        spi_doutReg = ~0;
        spi_d_outEn = 0;
        
        // Pulse the clock to get SB_IO initialized
        spi_clk = 1;
        #1;
        spi_clk = 0;
        
        // TestNoOp();
        // TestEcho();
        
        TestPixReset();
        TestPixStream();
        // TestPixI2CWriteRead();
        
        `Finish;
    end
endmodule
`endif
