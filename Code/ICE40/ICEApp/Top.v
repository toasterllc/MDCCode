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
`include "SDController.v"
`include "PixController.v"
`include "PixI2CMaster.v"
`include "RAMController.v"
`include "ICEAppTypes.v"

`ifdef SIM
`include "SDCardSim.v"
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
    
    output wire         sdcard_clk,
    inout wire          sdcard_cmd,
    inout wire[3:0]     sdcard_dat,
    
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
    // // ====================
    // // SD Clock (102 MHz)
    // // ====================
    // localparam SD_Clk_Freq = 102_000_000;
    // wire sd_clk;
    // ClockGen #(
    //     .FREQ(SD_Clk_Freq),
    //     .DIVR(0),
    //     .DIVF(33),
    //     .DIVQ(3),
    //     .FILTER_RANGE(2)
    // ) ClockGen_sd_clk(.clkRef(clk24mhz), .clk(sd_clk));
    
    
    // // ====================
    // // SD Clock (108 MHz)
    // // ====================
    // localparam SD_Clk_Freq = 108_000_000;
    // wire sd_clk;
    // ClockGen #(
    //     .FREQ(SD_Clk_Freq),
    //     .DIVR(0),
    //     .DIVF(35),
    //     .DIVQ(3),
    //     .FILTER_RANGE(2)
    // ) ClockGen_sd_clk(.clkRef(clk24mhz), .clk(sd_clk));
    
    // ====================
    // SD Clock (102 MHz)
    // ====================
    localparam SD_Clk_Freq = 102_000_000;
    wire sd_clk;
    ClockGen #(
        .FREQ(SD_Clk_Freq),
        .DIVR(0),
        .DIVF(33),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_sd_clk(.clkRef(clk24mhz), .clk(sd_clk));
    
    // ====================
    // SDController
    // ====================
    reg[1:0]    sd_clksrc_speed = 0;
    reg[3:0]    sd_clksrc_delay = 0;
    reg         sd_cmd_trigger = 0;
    reg[47:0]   sd_cmd_data = 0;
    reg[1:0]    sd_cmd_respType = 0;
    reg         sd_cmd_datInType = 0;
    wire        sd_cmd_done;
    wire        sd_resp_done;
    wire[47:0]  sd_resp_data;
    wire        sd_resp_crcErr;
    reg         sd_datOut_stop = 0;
    wire        sd_datOut_stopped;
    reg         sd_datOut_start = 0;
    wire        sd_datOut_ready;
    wire        sd_datOut_done;
    wire        sd_datOut_crcErr;
    wire        sd_datOutRead_clk;
    wire        sd_datOutRead_ready;
    wire        sd_datOutRead_trigger;
    wire[15:0]  sd_datOutRead_data;
    wire        sd_datIn_done;
    wire        sd_datIn_crcErr;
    wire[3:0]   sd_datIn_cmd6AccessMode;
    wire        sd_status_dat0Idle;
    
    SDController #(
        .ClkFreq(SD_Clk_Freq)
    ) SDController (
        .clk(sd_clk),
        
        .sdcard_clk(sdcard_clk),
        .sdcard_cmd(sdcard_cmd),
        .sdcard_dat(sdcard_dat),
        
        .clksrc_speed(sd_clksrc_speed),
        .clksrc_delay(sd_clksrc_delay),
        
        .cmd_trigger(sd_cmd_trigger),
        .cmd_data(sd_cmd_data),
        .cmd_respType(sd_cmd_respType),
        .cmd_datInType(sd_cmd_datInType),
        .cmd_done(sd_cmd_done),
        
        .resp_done(sd_resp_done),
        .resp_data(sd_resp_data),
        .resp_crcErr(sd_resp_crcErr),
        
        .datOut_stop(sd_datOut_stop),
        .datOut_stopped(sd_datOut_stopped),
        .datOut_start(sd_datOut_start),
        .datOut_done(sd_datOut_done),
        .datOut_crcErr(sd_datOut_crcErr),
        
        .datOutRead_clk(sd_datOutRead_clk),
        .datOutRead_ready(sd_datOutRead_ready),
        .datOutRead_trigger(sd_datOutRead_trigger),
        .datOutRead_data(sd_datOutRead_data),
        
        .datIn_done(sd_datIn_done),
        .datIn_crcErr(sd_datIn_crcErr),
        .datIn_cmd6AccessMode(sd_datIn_cmd6AccessMode),
        
        .status_dat0Idle(sd_status_dat0Idle)
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
    
    
    
    
    
    
    
    // // ====================
    // // Pix Clock (108 MHz)
    // // ====================
    // localparam Pix_Clk_Freq = 108_000_000;
    // wire pix_clk;
    // ClockGen #(
    //     .FREQ(Pix_Clk_Freq),
    //     .DIVR(0),
    //     .DIVF(35),
    //     .DIVQ(3),
    //     .FILTER_RANGE(2)
    // ) ClockGen_pix_clk(.clkRef(clk24mhz), .clk(pix_clk));
    
    localparam Pix_Clk_Freq = SD_Clk_Freq;
    wire pix_clk = sd_clk;
    
    // ====================
    // PixController
    // ====================
    reg[1:0]                            pixctrl_cmd = 0;
    reg[2:0]                            pixctrl_cmd_ramBlock = 0;
    wire                                pixctrl_readout_clk;
    wire                                pixctrl_readout_ready;
    wire                                pixctrl_readout_trigger;
    wire[15:0]                          pixctrl_readout_data;
    wire                                pixctrl_status_captureDone;
    wire[`RegWidth(ImageWidthMax)-1:0]  pixctrl_status_captureImageWidth;
    wire[`RegWidth(ImageHeightMax)-1:0] pixctrl_status_captureImageHeight;
    wire[17:0]                          pixctrl_status_captureHighlightCount;
    wire[17:0]                          pixctrl_status_captureShadowCount;
    wire                                pixctrl_status_readoutStarted;
    PixController #(
        .ClkFreq(Pix_Clk_Freq),
        .ImageWidthMax(ImageWidthMax),
        .ImageHeightMax(ImageHeightMax)
    ) PixController (
        .clk(pix_clk),
        
        .cmd(pixctrl_cmd),
        .cmd_ramBlock(pixctrl_cmd_ramBlock),
        
        .readout_clk(pixctrl_readout_clk),
        .readout_ready(pixctrl_readout_ready),
        .readout_trigger(pixctrl_readout_trigger),
        .readout_data(pixctrl_readout_data),
        
        .status_captureDone(pixctrl_status_captureDone),
        .status_captureImageWidth(pixctrl_status_captureImageWidth),
        .status_captureImageHeight(pixctrl_status_captureImageHeight),
        .status_captureHighlightCount(pixctrl_status_captureHighlightCount),
        .status_captureShadowCount(pixctrl_status_captureShadowCount),
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
    
    // Connect PixController.readout to SDController.datOutRead
    assign pixctrl_readout_clk = sd_datOutRead_clk;
    assign sd_datOutRead_ready = pixctrl_readout_ready;
    assign pixctrl_readout_trigger = sd_datOutRead_trigger;
    assign sd_datOutRead_data = pixctrl_readout_data;
    
    reg ctrl_pixCaptureTrigger = 0;
    `TogglePulse(pixctrl_captureTrigger, ctrl_pixCaptureTrigger, posedge, pix_clk);
    reg ctrl_pixReadoutTrigger = 0;
    `TogglePulse(pixctrl_readoutTrigger, ctrl_pixReadoutTrigger, posedge, pix_clk);
    `TogglePulse(pixctrl_sdDatOutStopped, sd_datOut_stopped, posedge, pix_clk);
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
    
    `ToggleAck(ctrl_sdCmdDone_, ctrl_sdCmdDoneAck, sd_cmd_done, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdRespDone_, ctrl_sdRespDoneAck, sd_resp_done, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatOutDone_, ctrl_sdDatOutDoneAck, sd_datOut_done, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatInDone_, ctrl_sdDatInDoneAck, sd_datIn_done, posedge, ctrl_clk);
    `Sync(ctrl_sdDat0Idle, sd_status_dat0Idle, posedge, ctrl_clk);
    
    `ToggleAck(ctrl_pixctrlStatusCaptureDone_, ctrl_pixctrlStatusCaptureDoneAck, pixctrl_statusCaptureDoneToggle, posedge, ctrl_clk);
    // `Sync(ctrl_pixctrlStatusCapturePixelDropped, pixctrl_status_capturePixelDropped, posedge, ctrl_clk);
    
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
                
                // Set SD clock source
                `Msg_Type_SDClkSrc: begin
                    $display("[CTRL] Got Msg_Type_SDClkSrc: delay=%0d speed=%0d",
                        ctrl_msgArg[`Msg_Arg_SDClkSrc_Delay_Bits],
                        ctrl_msgArg[`Msg_Arg_SDClkSrc_Speed_Bits]);
                    
                    // We don't need to synchronize `sd_clksrc_delay` into the sd_ domain,
                    // because it should only be set while the sd_ clock is disabled.
                    sd_clksrc_delay <= ctrl_msgArg[`Msg_Arg_SDClkSrc_Delay_Bits];
                    
                    case (ctrl_msgArg[`Msg_Arg_SDClkSrc_Speed_Bits])
                    `Msg_Arg_SDClkSrc_Speed_Off:    sd_clksrc_speed <= `SDController_ClkSrc_Speed_Off;
                    `Msg_Arg_SDClkSrc_Speed_Slow:   sd_clksrc_speed <= `SDController_ClkSrc_Speed_Slow;
                    `Msg_Arg_SDClkSrc_Speed_Fast:   sd_clksrc_speed <= `SDController_ClkSrc_Speed_Fast;
                    endcase
                end
                
                // Clock out SD command
                `Msg_Type_SDSendCmd: begin
                    $display("[CTRL] Got Msg_Type_SDSendCmd [respType:%0b]", ctrl_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]);
                    // Reset ctrl_sdCmdDone_ / ctrl_sdRespDone_ / ctrl_sdDatInDone_
                    if (!ctrl_sdCmdDone_) ctrl_sdCmdDoneAck <= !ctrl_sdCmdDoneAck;
                    
                    if (!ctrl_sdRespDone_ && ctrl_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]!==`Msg_Arg_SDSendCmd_RespType_None)
                        ctrl_sdRespDoneAck <= !ctrl_sdRespDoneAck;
                    
                    if (!ctrl_sdDatInDone_ && ctrl_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits]!==`Msg_Arg_SDSendCmd_DatInType_None)
                        ctrl_sdDatInDoneAck <= !ctrl_sdDatInDoneAck;
                    
                    case (ctrl_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits])
                    `Msg_Arg_SDSendCmd_RespType_None:   sd_cmd_respType <= `SDController_RespType_None;
                    `Msg_Arg_SDSendCmd_RespType_48:     sd_cmd_respType <= `SDController_RespType_48;
                    `Msg_Arg_SDSendCmd_RespType_136:    sd_cmd_respType <= `SDController_RespType_136;
                    endcase
                    
                    case (ctrl_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits])
                    `Msg_Arg_SDSendCmd_DatInType_None:  sd_cmd_datInType <= `SDController_DatInType_None;
                    `Msg_Arg_SDSendCmd_DatInType_512:   sd_cmd_datInType <= `SDController_DatInType_512;
                    endcase
                    
                    sd_cmd_data <= ctrl_msgArg[`Msg_Arg_SDSendCmd_CmdData_Bits];
                    sd_cmd_trigger <= !sd_cmd_trigger;
                end
                
                // Get SD status / response
                `Msg_Type_SDGetStatus: begin
                    $display("[CTRL] Got Msg_Type_SDGetStatus");
                    
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_CmdDone_Bits] <= !ctrl_sdCmdDone_;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_RespDone_Bits] <= !ctrl_sdRespDone_;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_RespCRCErr_Bits] <= sd_resp_crcErr;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_DatOutDone_Bits] <= !ctrl_sdDatOutDone_;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_DatOutCRCErr_Bits] <= sd_datOut_crcErr;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_DatInDone_Bits] <= !ctrl_sdDatInDone_;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_DatInCRCErr_Bits] <= sd_datIn_crcErr;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits] <= sd_datIn_cmd6AccessMode;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_Dat0Idle_Bits] <= ctrl_sdDat0Idle;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_Resp_Bits] <= sd_resp_data;
                end
                
                // `Msg_Type_PixReset: begin
                //     $display("[CTRL] Got Msg_Type_PixReset (rst=%b)", ctrl_msgArg[`Msg_Arg_PixReset_Val_Bits]);
                //     pix_rst_ <= ctrl_msgArg[`Msg_Arg_PixReset_Val_Bits];
                // end
                //
                // `Msg_Type_PixCapture: begin
                //     $display("[CTRL] Got Msg_Type_PixCapture (block=%b)", ctrl_msgArg[`Msg_Arg_PixCapture_DstBlock_Bits]);
                //
                //     // Reset `ctrl_pixctrlStatusCaptureDone_` if it's asserted
                //     if (!ctrl_pixctrlStatusCaptureDone_) ctrl_pixctrlStatusCaptureDoneAck <= !ctrl_pixctrlStatusCaptureDoneAck;
                //
                //     pixctrl_cmd_ramBlock <= ctrl_msgArg[`Msg_Arg_PixCapture_DstBlock_Bits];
                //     ctrl_pixCaptureTrigger <= !ctrl_pixCaptureTrigger;
                // end
                //
                // `Msg_Type_PixReadout: begin
                //     $display("[CTRL] Got Msg_Type_PixReadout (block=%b)", ctrl_msgArg[`Msg_Arg_PixReadout_SrcBlock_Bits]);
                //
                //     // Reset `ctrl_sdDatOutDone_` if it's asserted
                //     if (!ctrl_sdDatOutDone_) ctrl_sdDatOutDoneAck <= !ctrl_sdDatOutDoneAck;
                //
                //     pixctrl_cmd_ramBlock <= ctrl_msgArg[`Msg_Arg_PixReadout_SrcBlock_Bits];
                //     ctrl_pixReadoutTrigger <= !ctrl_pixReadoutTrigger;
                // end
                //
                // `Msg_Type_PixI2CTransaction: begin
                //     $display("[CTRL] Got Msg_Type_PixI2CTransaction");
                //
                //     // Reset `ctrl_pixi2c_done_` if it's asserted
                //     if (!ctrl_pixi2c_done_) ctrl_pixi2c_doneAck <= !ctrl_pixi2c_doneAck;
                //
                //     pixi2c_cmd_write <= ctrl_msgArg[`Msg_Arg_PixI2CTransaction_Write_Bits];
                //     pixi2c_cmd_regAddr <= ctrl_msgArg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits];
                //     pixi2c_cmd_dataLen <= (ctrl_msgArg[`Msg_Arg_PixI2CTransaction_DataLen_Bits]===`Msg_Arg_PixI2CTransaction_DataLen_2);
                //     pixi2c_cmd_writeData <= ctrl_msgArg[`Msg_Arg_PixI2CTransaction_WriteData_Bits];
                //     pixi2c_cmd_trigger <= !pixi2c_cmd_trigger;
                // end
                //
                // `Msg_Type_PixGetStatus: begin
                //     // $display("[CTRL] Got Msg_Type_PixGetStatus [I2CDone:%b, I2CErr:%b, I2CReadData:%b, CaptureDone:%b]",
                //     //     !ctrl_pixi2c_done_,
                //     //     pixi2c_status_err,
                //     //     pixi2c_status_readData,
                //     //     !ctrl_pixctrlStatusCaptureDone_
                //     // );
                //     ctrl_doutReg[`Resp_Arg_PixGetStatus_I2CDone_Bits] <= !ctrl_pixi2c_done_;
                //     ctrl_doutReg[`Resp_Arg_PixGetStatus_I2CErr_Bits] <= pixi2c_status_err;
                //     ctrl_doutReg[`Resp_Arg_PixGetStatus_I2CReadData_Bits] <= pixi2c_status_readData;
                //     ctrl_doutReg[`Resp_Arg_PixGetStatus_CaptureDone_Bits] <= !ctrl_pixctrlStatusCaptureDone_;
                //     ctrl_doutReg[`Resp_Arg_PixGetStatus_CapturePixelDropped_Bits] <= ctrl_pixctrlStatusCapturePixelDropped;
                // end
                
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
    
    wire        sdcard_clk;
    // tri1        sd_cmd;
    // tri1[3:0]   sd_dat;
    wire        sdcard_cmd;
    wire[3:0]   sdcard_dat;
    
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
    
    SDCardSim SDCardSim(
        .sd_clk(sdcard_clk),
        .sd_cmd(sdcard_cmd),
        .sd_dat(sdcard_dat)
    );
    
    localparam ImageWidth = 32;
    localparam ImageHeight = 4;
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
    
    localparam CMD0     = 6'd0;     // GO_IDLE_STATE
    localparam CMD2     = 6'd2;     // ALL_SEND_BIT_CID
    localparam CMD3     = 6'd3;     // SEND_BIT_RELATIVE_ADDR
    localparam CMD6     = 6'd6;     // SWITCH_FUNC
    localparam CMD7     = 6'd7;     // SELECT_CARD/DESELECT_CARD
    localparam CMD8     = 6'd8;     // SEND_BIT_IF_COND
    localparam CMD11    = 6'd11;    // VOLTAGE_SWITCH
    localparam CMD12    = 6'd12;    // STOP_TRANSMISSION
    localparam CMD25    = 6'd25;    // WRITE_MULTIPLE_BLOCK
    localparam CMD41    = 6'd41;    // SD_SEND_BIT_OP_COND
    localparam CMD55    = 6'd55;    // APP_CMD
    
    localparam ACMD23    = 6'd23;   // SET_WR_BLK_ERASE_COUNT
    
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
    
    task SendSDCmd(input[5:0] sdCmd, input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType, input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg[`Msg_Arg_Len-1] arg;
        arg = 0;
        arg[`Msg_Arg_SDSendCmd_RespType_Bits] = respType;
        arg[`Msg_Arg_SDSendCmd_DatInType_Bits] = datInType;
        arg[`Msg_Arg_SDSendCmd_CmdData_Bits] = {2'b01, sdCmd, sdArg, 7'b0, 1'b1};
        
        SendMsg(`Msg_Type_SDSendCmd, arg);
    end endtask
    
    task SendSDCmdResp(input[5:0] sdCmd, input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType, input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg[15:0] i;
        reg done;
        SendSDCmd(sdCmd, respType, datInType, sdArg);
        
        // Wait for SD command to be sent
        done = 0;
        for (i=0; i<1000 && !done; i++) begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            
            // If a response is expected, we're done when the response is received
            done = 1;
            done = done && resp[`Resp_Arg_SDGetStatus_CmdDone_Bits];
            if (respType !== `Msg_Arg_SDSendCmd_RespType_None) done = done && resp[`Resp_Arg_SDGetStatus_RespDone_Bits];
            if (datInType !== `Msg_Arg_SDSendCmd_DatInType_None) done = done && resp[`Resp_Arg_SDGetStatus_DatInDone_Bits];
        end
        
        if (!done) begin
            $display("[EXT] SD card response timeout ❌");
            `Finish;
        end
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
    
    task TestSDCMD0; begin
        SendSDCmdResp(CMD0, `Msg_Arg_SDSendCmd_RespType_None, `Msg_Arg_SDSendCmd_DatInType_None, 0);
    end endtask
    
    task TestSDCMD8; begin
        // ====================
        // Test SD CMD8 (SEND_IF_COND)
        // ====================
        reg[`Resp_Arg_SDGetStatus_Resp_Len-1:0] sdResp;
        
        // Send SD CMD8
        SendSDCmdResp(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'h000001AA);
        if (resp[`Resp_Arg_SDGetStatus_RespCRCErr_Bits] !== 1'b0) begin
            $display("[EXT] CRC error ❌");
            `Finish;
        end

        sdResp = resp[`Resp_Arg_SDGetStatus_Resp_Bits];
        if (sdResp[15:8] !== 8'hAA) begin
            $display("[EXT] Bad response: %h ❌", resp);
            `Finish;
        end
    end endtask
    
    task TestSDDatOut; begin
        // ====================
        // Test writing data to SD card / DatOut
        // ====================
        
        // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        SendSDCmdResp(CMD55, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
        SendSDCmdResp(ACMD23, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b1);
        
        // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        SendSDCmdResp(CMD25, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
        
        // Clock out data on DAT lines
        SendMsg(`Msg_Type_PixReadout, 0);
        
        // Wait until we're done clocking out data on DAT lines
        $display("[EXT] Waiting while data is written...");
        do begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
        end while(!resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits]);
        $display("[EXT] Done writing (SD resp: %b)", resp[`Resp_Arg_SDGetStatus_Resp_Bits]);
        
        // Check CRC status
        if (resp[`Resp_Arg_SDGetStatus_DatOutCRCErr_Bits] === 1'b0) begin
            $display("[EXT] DatOut CRC OK ✅");
        end else begin
            $display("[EXT] DatOut CRC bad ❌");
            `Finish;
        end
        
        // Stop transmission
        SendSDCmdResp(CMD12, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
    end endtask
    
    task TestSDDatIn; begin
        // ====================
        // Test CMD6 (SWITCH_FUNC) + DatIn
        // ====================
        
        // Send SD command CMD6 (SWITCH_FUNC)
        SendSDCmdResp(CMD6, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 32'h80FFFFF3);
        $display("[EXT] Waiting for DatIn to complete...");
        do begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
        end while(!resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        $display("[EXT] DatIn completed");

        // Check DatIn CRC status
        if (resp[`Resp_Arg_SDGetStatus_DatInCRCErr_Bits] === 1'b0) begin
            $display("[EXT] DatIn CRC OK ✅");
        end else begin
            $display("[EXT] DatIn CRC bad ❌");
            `Finish;
        end

        // Check the access mode from the CMD6 response
        if (resp[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits] === 4'h3) begin
            $display("[EXT] CMD6 access mode == 0x3 ✅");
        end else begin
            $display("[EXT] CMD6 access mode == 0x%h ❌", resp[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits]);
            `Finish;
        end
    end endtask
    
    
    task TestSDCMD2; begin
        // ====================
        // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
        //   Note: we expect CRC errors in the response because the R2
        //   response CRC doesn't follow the semantics of other responses
        // ====================
        
        // Send SD command CMD2 (ALL_SEND_CID)
        SendSDCmdResp(CMD2, `Msg_Arg_SDSendCmd_RespType_136, `Msg_Arg_SDSendCmd_DatInType_None, 0);
        $display("====================================================");
        $display("^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        $display("====================================================");
    end endtask
    
    task TestSDRespRecovery; begin
        reg done;
        reg[15:0] i;
        
        // Send an SD command that doesn't provide a response
        SendSDCmd(CMD0, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 0);
        $display("[EXT] Verifying that Resp times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            $display("[EXT] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
                resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
                resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
                resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);

            done = resp[`Resp_Arg_SDGetStatus_RespDone_Bits];
        end
        
        if (!done) begin
            $display("[EXT] Resp timeout ✅");
            $display("[EXT] Testing Resp after timeout...");
            TestSDCMD8();
            $display("[EXT] Resp Recovered ✅");
        
        end else begin
            $display("[EXT] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    task TestSDDatOutRecovery; begin
        reg done;
        reg[15:0] i;
        
        // Clock out data on DAT lines, but without the SD card
        // expecting data so that we don't get a response
        SendMsg(`Msg_Type_PixReadout, 0);
        
        #50000;
        
        // Verify that we timeout
        $display("[EXT] Verifying that DatOut times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            $display("[EXT] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
                resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
                resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
                resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);

            done = resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits];
        end

        if (!done) begin
            $display("[EXT] DatOut timeout ✅");
            $display("[EXT] Testing DatOut after timeout...");
            TestSDDatOut();
            $display("[EXT] DatOut Recovered ✅");

        end else begin
            $display("[EXT] DatOut didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    task TestSDDatInRecovery; begin
        reg done;
        reg[15:0] i;
        
        // Send SD command that doesn't respond on the DAT lines,
        // but specify that we expect DAT data
        SendSDCmd(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 0);
        $display("[EXT] Verifying that DatIn times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            $display("[EXT] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
                resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
                resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
                resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
            
            done = resp[`Resp_Arg_SDGetStatus_DatInDone_Bits];
        end

        if (!done) begin
            $display("[EXT] DatIn timeout ✅");
            $display("[EXT] Testing DatIn after timeout...");
            TestSDDatIn();
            $display("[EXT] DatIn Recovered ✅");
        
        end else begin
            $display("[EXT] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    // task TestPixReset; begin
    //     reg[`Msg_Arg_Len-1:0] arg;
    //
    //     // ====================
    //     // Test Pix reset
    //     // ====================
    //     arg = 0;
    //     arg[`Msg_Arg_PixReset_Val_Bits] = 0;
    //     SendMsg(`Msg_Type_PixReset, arg);
    //     if (pix_rst_ === arg[`Msg_Arg_PixReset_Val_Bits]) begin
    //         $display("[EXT] Reset=0 success ✅");
    //     end else begin
    //         $display("[EXT] Reset=0 failed ❌");
    //     end
    //
    //     arg = 0;
    //     arg[`Msg_Arg_PixReset_Val_Bits] = 1;
    //     SendMsg(`Msg_Type_PixReset, arg);
    //     if (pix_rst_ === arg[`Msg_Arg_PixReset_Val_Bits]) begin
    //         $display("[EXT] Reset=1 success ✅");
    //     end else begin
    //         $display("[EXT] Reset=1 failed ❌");
    //     end
    // end endtask
    //
    // task TestPixCapture; begin
    //     reg[`Msg_Arg_Len-1:0] arg;
    //
    //     arg = 0;
    //     arg[`Msg_Arg_PixReset_Val_Bits] = 1;
    //     SendMsg(`Msg_Type_PixReset, arg); // Deassert Pix reset
    //
    //     arg = 0;
    //     arg[`Msg_Arg_PixCapture_DstBlock_Bits] = 0;
    //     SendMsg(`Msg_Type_PixCapture, arg);
    //
    //     // Wait until the capture is done
    //     $display("[EXT] Waiting for capture to complete...");
    //     do begin
    //         // Request Pix status
    //         SendMsgResp(`Msg_Type_PixGetStatus, 0);
    //     end while(!resp[`Resp_Arg_PixGetStatus_CaptureDone_Bits]);
    //
    //     $display("[EXT] Capture done ✅");
    //
    //     if (!resp[`Resp_Arg_PixGetStatus_CapturePixelDropped_Bits]) begin
    //         $display("[EXT] No dropped pixels ✅");
    //     end else begin
    //         $display("[EXT] Dropped pixels ❌");
    //     end
    // end endtask
    //
    // task TestPixI2CWriteRead; begin
    //     reg[`Msg_Arg_Len-1:0] arg;
    //     reg done;
    //
    //     // ====================
    //     // Test PixI2C Write (len=2)
    //     // ====================
    //     arg = 0;
    //     arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 1;
    //     arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_2;
    //     arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h4242;
    //     arg[`Msg_Arg_PixI2CTransaction_WriteData_Bits] = 16'hCAFE;
    //     SendMsg(`Msg_Type_PixI2CTransaction, arg);
    //
    //     done = 0;
    //     while (!done) begin
    //         SendMsgResp(`Msg_Type_PixGetStatus, 0);
    //         $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
    //             resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
    //         );
    //
    //         done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
    //     end
    //
    //     if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
    //         $display("[EXT] Write success ✅");
    //     end else begin
    //         $display("[EXT] Write failed ❌");
    //     end
    //
    //     // ====================
    //     // Test PixI2C Read (len=2)
    //     // ====================
    //     arg = 0;
    //     arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 0;
    //     arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_2;
    //     arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h4242;
    //     SendMsg(`Msg_Type_PixI2CTransaction, arg);
    //
    //     done = 0;
    //     while (!done) begin
    //         SendMsgResp(`Msg_Type_PixGetStatus, 0);
    //         $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
    //             resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
    //         );
    //
    //         done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
    //     end
    //
    //     if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
    //         $display("[EXT] Read success ✅");
    //     end else begin
    //         $display("[EXT] Read failed ❌");
    //     end
    //
    //     if (resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits] === 16'hCAFE) begin
    //         $display("[EXT] Read correct data ✅ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]);
    //     end else begin
    //         $display("[EXT] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]);
    //         `Finish;
    //     end
    //
    //     // ====================
    //     // Test PixI2C Write (len=1)
    //     // ====================
    //     arg = 0;
    //     arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 1;
    //     arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_1;
    //     arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h8484;
    //     arg[`Msg_Arg_PixI2CTransaction_WriteData_Bits] = 16'h0037;
    //     SendMsg(`Msg_Type_PixI2CTransaction, arg);
    //
    //     done = 0;
    //     while (!done) begin
    //         SendMsgResp(`Msg_Type_PixGetStatus, 0);
    //         $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
    //             resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
    //         );
    //
    //         done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
    //     end
    //
    //     if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
    //         $display("[EXT] Write success ✅");
    //     end else begin
    //         $display("[EXT] Write failed ❌");
    //     end
    //
    //     // ====================
    //     // Test PixI2C Read (len=1)
    //     // ====================
    //     arg = 0;
    //     arg[`Msg_Arg_PixI2CTransaction_Write_Bits] = 0;
    //     arg[`Msg_Arg_PixI2CTransaction_DataLen_Bits] = `Msg_Arg_PixI2CTransaction_DataLen_1;
    //     arg[`Msg_Arg_PixI2CTransaction_RegAddr_Bits] = 16'h8484;
    //     SendMsg(`Msg_Type_PixI2CTransaction, arg);
    //
    //     done = 0;
    //     while (!done) begin
    //         SendMsgResp(`Msg_Type_PixGetStatus, 0);
    //         $display("[EXT] PixI2C status: done:%b err:%b readData:0x%x",
    //             resp[`Resp_Arg_PixGetStatus_I2CDone_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CErr_Bits],
    //             resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]
    //         );
    //
    //         done = resp[`Resp_Arg_PixGetStatus_I2CDone_Bits];
    //     end
    //
    //     if (!resp[`Resp_Arg_PixGetStatus_I2CErr_Bits]) begin
    //         $display("[EXT] Read success ✅");
    //     end else begin
    //         $display("[EXT] Read failed ❌");
    //     end
    //
    //     if ((resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF) === 16'h0037) begin
    //         $display("[EXT] Read correct data ✅ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF);
    //     end else begin
    //         $display("[EXT] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_PixGetStatus_I2CReadData_Bits]&16'h00FF);
    //     end
    // end endtask
    
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        
        // Set our initial state
        ctrl_clk = 0;
        ctrl_rst = 1;
        ctrl_diReg = ~0;
        #1;
        
        // Disable SD clock
        SendMsg(`Msg_Type_SDClkSrc, `Msg_Arg_SDClkSrc_Speed_Off);

        // Set SD clock source
        SendMsg(`Msg_Type_SDClkSrc, `Msg_Arg_SDClkSrc_Speed_Fast);
        
        // TestNoOp();
        // TestEcho();
        
        // // Do Pix stuff before SD stuff, so that the RAM is populated with an image, so that
        // // the RAM has valid content for when we do the readout to write to the SD card.
        // TestPixReset();
        // TestPixCapture();
        // TestPixI2CWriteRead();
        
        TestSDCMD0();
        TestSDCMD8();
        // TestSDDatOut();
        // TestSDCMD2();
        // TestSDDatIn();
        // TestSDRespRecovery();
        // TestSDDatOutRecovery();
        // TestSDDatInRecovery();
        `Finish;
        
        // forever begin
        //     i = $urandom%8;
        //     case (i)
        //     0: TestSDCMD0();
        //     1: TestSDCMD8();
        //     2: TestSDDatOut();
        //     3: TestSDCMD2();
        //     4: TestSDDatIn();
        //     5: TestSDRespRecovery();
        //     6: TestSDDatOutRecovery();
        //     7: TestSDDatInRecovery();
        //     endcase
        // end
        
    end
endmodule
`endif
