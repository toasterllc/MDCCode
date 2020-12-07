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
    
    input wire          ctrl_clk,
    input wire          ctrl_rst,
    input wire          ctrl_di,
    output wire         ctrl_do,
    
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
    `ToggleAck(ctrl_pixi2c_done_, ctrl_pixi2c_doneAck, pixi2c_status_done, posedge, ctrl_clk);
    
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
    wire        pixctrl_readout_done;
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
        .readout_done(pixctrl_readout_done),
        
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
    
    reg ctrl_pixCaptureTrigger = 0;
    `TogglePulse(pixctrl_captureTrigger, ctrl_pixCaptureTrigger, posedge, pix_clk);
    reg ctrl_pixReadoutTrigger = 0;
    `TogglePulse(pixctrl_readoutTrigger, ctrl_pixReadoutTrigger, posedge, pix_clk);
    reg pixctrl_statusCaptureDoneToggle = 0;
    
    localparam PixCtrl_State_Idle           = 0;    // +0
    localparam PixCtrl_State_Capture        = 1;    // +0
    localparam PixCtrl_State_Readout        = 2;    // +2
    localparam Data_State_Count             = 5;
    reg[`RegWidth(Data_State_Count-1)-1:0] pixctrl_state = 0;
    always @(posedge pix_clk) begin
        pixctrl_cmd <= `PixController_Cmd_None;
        
        case (pixctrl_state)
        PixCtrl_State_Idle: begin
        end
        
        PixCtrl_State_Capture: begin
            pixctrl_cmd <= `PixController_Cmd_Capture;
            pixctrl_state <= PixCtrl_State_Idle;
        end
        
        PixCtrl_State_Readout: begin
            $display("[PixCtrl] Readout triggered");
            // Tell SDController DatOut to stop so that the FIFO isn't accessed until
            // the FIFO is reset and new data is available.
            sd_datOut_stop <= !sd_datOut_stop;
            pixctrl_state <= PixCtrl_State_Readout+1;
        end
        
        PixCtrl_State_Readout+1: begin
            // Wait until SDController DatOut is stopped
            if (pixctrl_sdDatOutStopped) begin
                // Tell PixController to start readout
                pixctrl_cmd <= `PixController_Cmd_Readout;
                pixctrl_state <= PixCtrl_State_Readout+2;
            end
        end
        
        PixCtrl_State_Readout+2: begin
            // Wait until PixController readout starts
            if (pixctrl_status_readoutStarted) begin
                // Start SD DatOut now that readout has started (and therefore
                // the FIFO has been reset)
                sd_datOut_start <= !sd_datOut_start;
            end
        end
        endcase
        
        if (pixctrl_captureTrigger) begin
            // led <= 4'b1111;
            pixctrl_state <= PixCtrl_State_Capture;
        end
        
        if (pixctrl_readoutTrigger) begin
            pixctrl_state <= PixCtrl_State_Readout;
        end
        
        // TODO: create a primitive to convert a pulse in a source clock domain to a ToggleAck in a destination clock domain
        if (pixctrl_status_captureDone) pixctrl_statusCaptureDoneToggle <= !pixctrl_statusCaptureDoneToggle;
    end
    
    
    
    
    
    
    
    
    // ====================
    // Control State Machine
    // ====================
    reg[1:0] ctrl_state = 0;
    reg[6:0] ctrl_counter = 0;
    // +5 for delay states, so that clients send an extra byte before receiving the response
    reg[`Resp_Len+5-1:0] ctrl_doutReg = 0;
    
    wire ctrl_rst_;
    wire ctrl_din;
    reg[`Msg_Len-1:0] ctrl_dinReg = 0;
    wire[`Msg_Type_Len-1:0] ctrl_msgType = ctrl_dinReg[`Msg_Type_Bits];
    wire[`Msg_Arg_Len-1:0] ctrl_msgArg = ctrl_dinReg[`Msg_Arg_Bits];
    
    `ToggleAck(ctrl_pixctrlStatusCaptureDone_, ctrl_pixctrlStatusCaptureDoneAck, pixctrl_statusCaptureDoneToggle, posedge, ctrl_clk);
    `Sync(ctrl_pixctrlStatusCapturePixelDropped, pixctrl_status_capturePixelDropped, posedge, ctrl_clk);
    
    always @(posedge ctrl_clk, negedge ctrl_rst_) begin
        if (!ctrl_rst_) begin
            ctrl_state <= 0;
        
        end else begin
            ctrl_dinReg <= ctrl_dinReg<<1|ctrl_din;
            ctrl_doutReg <= ctrl_doutReg<<1|1'b1;
            ctrl_counter <= ctrl_counter-1;
            
            case (ctrl_state)
            0: begin
                ctrl_counter <= `Msg_Len-1;
                ctrl_state <= 1;
            end
            
            1: begin
                if (!ctrl_counter) begin
                    ctrl_state <= 2;
                end
            end
            
            2: begin
                // $display("[CTRL] Got command: %b [cmd: %0d, arg: %0d]", ctrl_dinReg, ctrl_msgType, ctrl_msgArg);
                case (ctrl_msgType)
                // Echo
                `Msg_Type_Echo: begin
                    $display("[CTRL] Got Msg_Type_Echo: %0h", ctrl_msgArg[`Msg_Arg_Echo_Msg_Bits]);
                    ctrl_doutReg[`Resp_Arg_Echo_Msg_Bits] <= ctrl_msgArg[`Msg_Arg_Echo_Msg_Bits];
                end
                
                `Msg_Type_PixReset: begin
                    $display("[CTRL] Got Msg_Type_PixReset (rst=%b)", ctrl_msgArg[`Msg_Arg_PixReset_Val_Bits]);
                    pix_rst_ <= ctrl_msgArg[`Msg_Arg_PixReset_Val_Bits];
                end
                
                `Msg_Type_PixCapture: begin
                    $display("[CTRL] Got Msg_Type_PixCapture (block=%b)", ctrl_msgArg[`Msg_Arg_PixCapture_DstBlock_Bits]);
                    
                    // Reset `ctrl_pixctrlStatusCaptureDone_` if it's asserted
                    if (!ctrl_pixctrlStatusCaptureDone_) ctrl_pixctrlStatusCaptureDoneAck <= !ctrl_pixctrlStatusCaptureDoneAck;
                    
                    pixctrl_cmd_ramBlock <= ctrl_msgArg[`Msg_Arg_PixCapture_DstBlock_Bits];
                    ctrl_pixCaptureTrigger <= !ctrl_pixCaptureTrigger;
                end
                
                `Msg_Type_PixReadout: begin
                    $display("[CTRL] Got Msg_Type_PixReadout (block=%b)", ctrl_msgArg[`Msg_Arg_PixReadout_SrcBlock_Bits]);
                    
                    // Reset `ctrl_sdDatOutDone_` if it's asserted
                    if (!ctrl_sdDatOutDone_) ctrl_sdDatOutDoneAck <= !ctrl_sdDatOutDoneAck;
                    
                    pixctrl_cmd_ramBlock <= ctrl_msgArg[`Msg_Arg_PixReadout_SrcBlock_Bits];
                    ctrl_pixReadoutTrigger <= !ctrl_pixReadoutTrigger;
                end
                
                `Msg_Type_PixI2CTransaction: begin
                    $display("[CTRL] Got Msg_Type_PixI2CTransaction");
                    
                    // Reset `ctrl_pixi2c_done_` if it's asserted
                    if (!ctrl_pixi2c_done_) ctrl_pixi2c_doneAck <= !ctrl_pixi2c_doneAck;
                    
                    pixi2c_cmd_write <= ctrl_msgArg[`Msg_Arg_PixI2CTransaction_Write_Bits];
                    pixi2c_cmd_regAddr <= ctrl_msgArg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits];
                    pixi2c_cmd_dataLen <= (ctrl_msgArg[`Msg_Arg_PixI2CTransaction_DataLen_Bits]===`Msg_Arg_PixI2CTransaction_DataLen_2);
                    pixi2c_cmd_writeData <= ctrl_msgArg[`Msg_Arg_PixI2CTransaction_WriteData_Bits];
                    pixi2c_cmd_trigger <= !pixi2c_cmd_trigger;
                end
                
                `Msg_Type_PixGetStatus: begin
                    // $display("[CTRL] Got Msg_Type_PixGetStatus [I2CDone:%b, I2CErr:%b, I2CReadData:%b, CaptureDone:%b]",
                    //     !ctrl_pixi2c_done_,
                    //     pixi2c_status_err,
                    //     pixi2c_status_readData,
                    //     !ctrl_pixctrlStatusCaptureDone_
                    // );
                    ctrl_doutReg[`Resp_Arg_PixGetStatus_I2CDone_Bits] <= !ctrl_pixi2c_done_;
                    ctrl_doutReg[`Resp_Arg_PixGetStatus_I2CErr_Bits] <= pixi2c_status_err;
                    ctrl_doutReg[`Resp_Arg_PixGetStatus_I2CReadData_Bits] <= pixi2c_status_readData;
                    ctrl_doutReg[`Resp_Arg_PixGetStatus_CaptureDone_Bits] <= !ctrl_pixctrlStatusCaptureDone_;
                    ctrl_doutReg[`Resp_Arg_PixGetStatus_CapturePixelDropped_Bits] <= ctrl_pixctrlStatusCapturePixelDropped;
                end
                
                `Msg_Type_NoOp: begin
                    $display("[CTRL] Got Msg_Type_None");
                end
                
                default: begin
                    $display("[CTRL] BAD COMMAND: %0d ❌", ctrl_msgType);
                    `Finish;
                end
                endcase
                
                ctrl_state <= 0;
            end
            endcase
        end
    end
    
    // ====================
    // Pin: ctrl_rst
    // ====================
    wire ctrl_rst_tmp;
    assign ctrl_rst_ = !ctrl_rst_tmp;
    SB_IO #(
        .PIN_TYPE(6'b0000_01),
        .PULLUP(1'b1)
    ) SB_IO_ctrl_rst (
        .PACKAGE_PIN(ctrl_rst),
        .D_IN_0(ctrl_rst_tmp)
    );
    
    // ====================
    // Pin: ctrl_di
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b0000_00),
        .PULLUP(1'b1)
    ) SB_IO_ctrl_clk (
        .INPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_di),
        .D_IN_0(ctrl_din)
    );
    
    // ====================
    // Pin: ctrl_do
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_01),
        .PULLUP(1'b1)
    ) SB_IO_ctrl_do (
        .OUTPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_do),
        .OUTPUT_ENABLE(1'b1),
        .D_OUT_0(ctrl_doutReg[$size(ctrl_doutReg)-1])
    );
endmodule







`ifdef SIM
module Testbench();
    reg         clk24mhz;
    
    reg         ctrl_clk;
    reg         ctrl_rst;
    tri1        ctrl_di;
    tri1        ctrl_do;
    
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
    
    localparam CTRL_CLK_DELAY = 21;
    
    reg[`Msg_Len-1:0] ctrl_diReg;
    reg[`Resp_Len-1:0] ctrl_doReg;
    reg[`Resp_Len-1:0] resp;
    
    always @(posedge ctrl_clk) begin
        ctrl_diReg <= ctrl_diReg<<1|1'b1;
        ctrl_doReg <= ctrl_doReg<<1|ctrl_do;
    end
    
    assign ctrl_di = ctrl_diReg[`Msg_Len-1];
    
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        ctrl_rst = 0;
        #1; // Let `ctrl_rst` change take effect
            ctrl_diReg = {typ, arg};
            for (i=0; i<`Msg_Len; i++) begin
                ctrl_clk = 1;
                #(CTRL_CLK_DELAY);
                ctrl_clk = 0;
                #(CTRL_CLK_DELAY);
            end
            
            // Clock out dummy byte
            for (i=0; i<8; i++) begin
                ctrl_clk = 1;
                #(CTRL_CLK_DELAY);
                ctrl_clk = 0;
                #(CTRL_CLK_DELAY);
            end
        ctrl_rst = 1;
        #1; // Let `ctrl_rst` change take effect
    end endtask
    
    task SendMsgResp(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        SendMsg(typ, arg);
        
        // Load the response
        ctrl_rst = 0;
        #1; // Let `ctrl_rst` change take effect
            for (i=0; i<`Msg_Len; i++) begin
                ctrl_clk = 1;
                #(CTRL_CLK_DELAY);
                ctrl_clk = 0;
                #(CTRL_CLK_DELAY);
            end
        ctrl_rst = 1;
        #1; // Let `ctrl_rst` change take effect
        
        resp = ctrl_doReg;
    end endtask
    
    task TestNoOp; begin
        // ====================
        // Test NoOp command
        // ====================

        SendMsgResp(`Msg_Type_NoOp, 56'h66554433221100);
        if (resp === 64'hFFFFFFFFFFFFFFFF) begin
            $display("Response OK: %h ✅", resp);
        end else begin
            $display("Bad response: %h ❌", resp);
            `Finish;
        end
    end endtask
    
    task TestEcho; begin
        // ====================
        // Test Echo command
        // ====================
        reg[`Msg_Arg_Echo_Msg_Len-1:0] arg;
        arg = `Msg_Arg_Echo_Msg_Len'h66554433221100;
        
        SendMsgResp(`Msg_Type_Echo, arg);
        if (resp[`Resp_Arg_Echo_Msg_Bits] === arg) begin
            $display("Response OK: %h ✅", resp);
        end else begin
            $display("Bad response: %h ❌", resp);
            `Finish;
        end
    end endtask
    
    task TestPixReset; begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        // ====================
        // Test Pix reset
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixReset_Val_Bits] = 0;
        SendMsg(`Msg_Type_PixReset, arg);
        if (pix_rst_ === arg[`Msg_Arg_PixReset_Val_Bits]) begin
            $display("[EXT] Reset=0 success ✅");
        end else begin
            $display("[EXT] Reset=0 failed ❌");
        end

        arg = 0;
        arg[`Msg_Arg_PixReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_PixReset, arg);
        if (pix_rst_ === arg[`Msg_Arg_PixReset_Val_Bits]) begin
            $display("[EXT] Reset=1 success ✅");
        end else begin
            $display("[EXT] Reset=1 failed ❌");
        end
    end endtask

    task TestPixCapture; begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        arg = 0;
        arg[`Msg_Arg_PixReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_PixReset, arg); // Deassert Pix reset

        arg = 0;
        arg[`Msg_Arg_PixCapture_DstBlock_Bits] = 0;
        SendMsg(`Msg_Type_PixCapture, arg);

        // Wait until the capture is done
        $display("[EXT] Waiting for capture to complete...");
        do begin
            // Request Pix status
            SendMsgResp(`Msg_Type_PixGetStatus, 0);
        end while(!resp[`Resp_Arg_PixGetStatus_CaptureDone_Bits]);
        
        $display("[EXT] Capture done ✅");
        
        if (!resp[`Resp_Arg_PixGetStatus_CapturePixelDropped_Bits]) begin
            $display("[EXT] No dropped pixels ✅");
        end else begin
            $display("[EXT] Dropped pixels ❌");
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
        SendMsg(`Msg_Type_PixI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsgResp(`Msg_Type_PixGetStatus, 0);
            $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end
        
        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[EXT] Write success ✅");
        end else begin
            $display("[EXT] Write failed ❌");
        end
        
        // ====================
        // Test PixI2C Read (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_2;
        arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h4242;
        SendMsg(`Msg_Type_PixI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsgResp(`Msg_Type_PixGetStatus, 0);
            $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end

        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[EXT] Read success ✅");
        end else begin
            $display("[EXT] Read failed ❌");
        end

        if (resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits] === 16'hCAFE) begin
            $display("[EXT] Read correct data ✅ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]);
        end else begin
            $display("[EXT] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]);
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
        SendMsg(`Msg_Type_PixI2CTransaction, arg);

        done = 0;
        while (!done) begin
            SendMsgResp(`Msg_Type_PixGetStatus, 0);
            $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end

        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[EXT] Write success ✅");
        end else begin
            $display("[EXT] Write failed ❌");
        end

        // ====================
        // Test PixI2C Read (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_1;
        arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h8484;
        SendMsg(`Msg_Type_PixI2CTransaction, arg);

        done = 0;
        while (!done) begin
            SendMsgResp(`Msg_Type_PixGetStatus, 0);
            $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
                resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
            );

            done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
        end

        if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
            $display("[EXT] Read success ✅");
        end else begin
            $display("[EXT] Read failed ❌");
        end

        if ((resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF) === 16'h0037) begin
            $display("[EXT] Read correct data ✅ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF);
        end else begin
            $display("[EXT] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF);
        end
    end endtask
    
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        
        // Set our initial state
        ctrl_clk = 0;
        ctrl_rst = 1;
        ctrl_diReg = ~0;
        #1;
        
        TestNoOp();
        TestEcho();
        
        TestPixReset();
        TestPixCapture();
        TestPixI2CWriteRead();
        `Finish;
        
    end
endmodule
`endif
