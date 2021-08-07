`include "Util.v"
`include "Sync.v"
`include "ToggleAck.v"
`include "SDController.v"
`include "ICEAppTypes.v"
`include "ClockGen.v"
`include "ImgController.v"
`include "ImgI2CMaster.v"

`ifdef SIM
// SDCARDSIM_LVS_INIT_IGNORE_5MS: Don't require waiting for 5ms, because that takes way too long in simulation
`define SDCARDSIM_LVS_INIT_IGNORE_5MS
`include "SDCardSim.v"

`include "ImgSim.v"
`include "ImgI2CSlaveSim.v"

// // MOBILE_SDR_INIT_VAL: Initialize the memory because ImgController reads a few words
// // beyond the image that's written to the RAM, and we don't want to read `x` (don't care)
// // when that happens
// `define MOBILE_SDR_INIT_VAL 16'hCAFE
`include "mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    input wire          ice_msp_spi_clk,
    inout wire          ice_msp_spi_data,
    
    // SD port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    
    // IMG port
    input wire          img_dclk,
    input wire[11:0]    img_d,
    input wire          img_fv,
    input wire          img_lv,
    output reg          img_rst_ = 0,
    output wire         img_sclk,
    inout wire          img_sdata,
    
    // RAM port
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[11:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq,
    
    // LED port
    output reg[3:0]     ice_led = 0
    
`ifdef SIM
    // Exported so that the sim can verify that the state machine is in reset
    , output wire         sim_rst_
`endif
);
    // ====================
    // spi_clk
    // ====================
    wire spi_clk;
    
    
    
    
    
    
    
    // ====================
    // ImgI2CMaster
    // ====================
    localparam ImgI2CSlaveAddr = 7'h10;
    reg imgi2c_cmd_write = 0;
    reg[15:0] imgi2c_cmd_regAddr = 0;
    reg imgi2c_cmd_dataLen = 0;
    reg[15:0] imgi2c_cmd_writeData = 0;
    reg imgi2c_cmd_trigger = 0;
    wire imgi2c_status_done;
    wire imgi2c_status_err;
    wire[15:0] imgi2c_status_readData;
    `ToggleAck(spi_imgi2c_done_, spi_imgi2c_doneAck, imgi2c_status_done, posedge, spi_clk);
    
    ImgI2CMaster #(
        .ClkFreq(16_000_000),
`ifdef SIM
        .I2CClkFreq(4_000_000)
`else
        .I2CClkFreq(100_000) // TODO: try 400_000 (the max frequency) to see if it works. if not, the pullup's likely too weak.
`endif
    ) ImgI2CMaster (
        .clk(ice_img_clk16mhz),
        
        .cmd_slaveAddr(ImgI2CSlaveAddr),
        .cmd_write(imgi2c_cmd_write),
        .cmd_regAddr(imgi2c_cmd_regAddr),
        .cmd_dataLen(imgi2c_cmd_dataLen),
        .cmd_writeData(imgi2c_cmd_writeData),
        .cmd_trigger(imgi2c_cmd_trigger), // Toggle
        
        .status_done(imgi2c_status_done), // Toggle
        .status_err(imgi2c_status_err),
        .status_readData(imgi2c_status_readData),
        
        .i2c_clk(img_sclk),
        .i2c_data(img_sdata)
    );
    
    
    
    
    
    
    
    // ====================
    // Img Clock (108 MHz)
    // ====================
    localparam Img_Clk_Freq = 108_000_000;
    wire img_clk;
    ClockGen #(
        .FREQOUT(Img_Clk_Freq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_img_clk(.clkRef(ice_img_clk16mhz), .clk(img_clk));
    
    // ====================
    // ImgController
    // ====================
    reg                                 imgctrl_cmd_capture = 0;
    reg[0:0]                            imgctrl_cmd_ramBlock = 0;
    wire                                imgctrl_readout_clk;
    wire                                imgctrl_readout_ready;
    wire                                imgctrl_readout_trigger;
    wire[15:0]                          imgctrl_readout_data;
    wire                                imgctrl_status_captureDone;
    wire[`RegWidth(ImageWidthMax)-1:0]  imgctrl_status_captureImageWidth;
    wire[`RegWidth(ImageHeightMax)-1:0] imgctrl_status_captureImageHeight;
    wire[17:0]                          imgctrl_status_captureHighlightCount;
    wire[17:0]                          imgctrl_status_captureShadowCount;
    ImgController #(
        .ClkFreq(Img_Clk_Freq),
        .ImageWidthMax(ImageWidthMax),
        .ImageHeightMax(ImageHeightMax)
    ) ImgController (
        .clk(img_clk),
        
        .cmd_capture(imgctrl_cmd_capture),
        .cmd_ramBlock(imgctrl_cmd_ramBlock),
        
        .readout_clk(imgctrl_readout_clk),
        .readout_ready(imgctrl_readout_ready),
        .readout_trigger(imgctrl_readout_trigger),
        .readout_data(imgctrl_readout_data),
        
        .status_captureDone(imgctrl_status_captureDone),
        .status_captureImageWidth(imgctrl_status_captureImageWidth),
        .status_captureImageHeight(imgctrl_status_captureImageHeight),
        .status_captureHighlightCount(imgctrl_status_captureHighlightCount),
        .status_captureShadowCount(imgctrl_status_captureShadowCount),
        
        .img_dclk(img_dclk),
        .img_d(img_d),
        .img_fv(img_fv),
        .img_lv(img_lv),
        
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
    
    // reg img_captureDone = 0;
    // reg img_readoutStarted = 0;
    //
    // localparam Img_State_Idle       = 0;    // +0
    // localparam Img_State_Capture    = 1;    // +1
    // localparam Img_State_Readout    = 3;    // +0
    // localparam Img_State_Count      = 4;
    // reg[`RegWidth(Img_State_Count-1)-1:0] img_state = 0;
    // always @(posedge img_clk) begin
    //     imgctrl_cmd <= `ImgController_Cmd_None;
    //
    //     case (img_state)
    //     Img_State_Idle: begin
    //     end
    //
    //     // TODO: consider making ImgController just use a toggle input for the 2 commands (capture and readout)?
    //     Img_State_Capture: begin
    //         // Start a capture
    //         imgctrl_cmd <= `ImgController_Cmd_Capture;
    //         img_state <= Img_State_Idle;
    //     end
    //
    //     // Img_State_Capture+1: begin
    //     //     // Wait for the capture to complete, and then start readout
    //     //     if (imgctrl_status_captureDone) begin
    //     //         imgctrl_cmd <= `ImgController_Cmd_Readout;
    //     //         img_state <= Img_State_Readout;
    //     //     end
    //     // end
    //
    //     Img_State_Readout: begin
    //         // Wait for readout to start, and then signal so via img_readoutStarted
    //         if (imgctrl_status_readoutStarted) begin
    //             img_readoutStarted <= !img_readoutStarted;
    //             img_state <= Img_State_Idle;
    //         end
    //     end
    //     endcase
    //
    //     if (img_captureTrigger) begin
    //         // ice_led <= 4'b1111;
    //         img_state <= Img_State_Capture;
    //     end
    //
    //     // Convert `imgctrl_status_captureDone` pulse into a toggle
    //     if (imgctrl_status_captureDone) img_captureDone <= !img_captureDone;
    // end
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // ====================
    // SD Clock (102 MHz)
    // ====================
    localparam SD_Clk_Freq = 102_000_000;
    wire sd_clk_int;
    ClockGen #(
        .FREQOUT(SD_Clk_Freq),
        .DIVR(0),
        .DIVF(50),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_sd_clk_int(.clkRef(ice_img_clk16mhz), .clk(sd_clk_int));
    
    // // ====================
    // // SD Clock (50 MHz)
    // // ====================
    // localparam SD_Clk_Freq = 50_000_000;
    // wire sd_clk_int;
    // ClockGen #(
    //     .FREQOUT(SD_Clk_Freq),
    //     .DIVR(0),
    //     .DIVF(49),
    //     .DIVQ(4),
    //     .FILTER_RANGE(1)
    // ) ClockGen_sd_clk_int(.clkRef(ice_img_clk16mhz), .clk(sd_clk_int));

    // ====================
    // SDController
    // ====================
    reg         sd_init_en_ = 0;
    reg         sd_init_trigger = 0;
    reg[1:0]    sd_init_clk_speed = 0;
    reg[3:0]    sd_init_clk_delay = 0;
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
        .clk(sd_clk_int),

        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat),

        .init_en_(sd_init_en_),
        .init_trigger(sd_init_trigger),
        .init_clk_speed(sd_init_clk_speed),
        .init_clk_delay(sd_init_clk_delay),

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
    
    // Connect imgctrl_readout_* to sd_datOutRead_*
    assign imgctrl_readout_clk = sd_datOutRead_clk;
    assign sd_datOutRead_ready = imgctrl_readout_ready;
    assign imgctrl_readout_trigger = sd_datOutRead_trigger;
    assign sd_datOutRead_data = imgctrl_readout_data;
    
    
    
    
    
    
    
    // ====================
    // spi_rst_ Generation
    // ====================
    // SPIRstTicks must be a power of 2 (since it determines the size of the spirst_counter
    // register), and must be longer than the time to send a SPI message, otherwise a reset
    // could be triggered during a SPI transaction.
    localparam SPIRstTicks = 1<<8; // 256 ticks @ ice_img_clk16mhz (16 MHz) == 16 us
    reg[`RegWidth(SPIRstTicks-1)-1:0] spirst_counter = 0;
    wire spirst_clk = ice_img_clk16mhz;
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
    
    // SD nets
    `ToggleAck(spi_sdCmdDone_, spi_sdCmdDoneAck, sd_cmd_done, posedge, spi_clk);
    `ToggleAck(spi_sdRespDone_, spi_sdRespDoneAck, sd_resp_done, posedge, spi_clk);
    `ToggleAck(spi_sdDatOutDone_, spi_sdDatOutDoneAck, sd_datOut_done, posedge, spi_clk);
    `ToggleAck(spi_sdDatInDone_, spi_sdDatInDoneAck, sd_datIn_done, posedge, spi_clk);
    `Sync(spi_sdDat0Idle, sd_status_dat0Idle, posedge, spi_clk);
    
    // IMG nets
    `ToggleAck(spi_imgCaptureDone_, spi_imgCaptureDoneAck, imgctrl_status_captureDone, posedge, spi_clk);
    
    // SPI control nets
    localparam TurnaroundDelay = 8;
    localparam TurnaroundInherentDelay = 2; // TODO: =4 when `SB_IO_ice_msp_spi_data` registers the input
    localparam TurnaroundExtraDelay = TurnaroundDelay-TurnaroundInherentDelay;
    localparam MsgCycleCount = `Msg_Len+TurnaroundExtraDelay-2;
    localparam RespCycleCount = `Resp_Len;
    
    reg[`Msg_Len-1:0] spi_dataInReg = 0;
    wire[`Msg_Type_Len-1:0] spi_msgType = spi_dataInReg[`Msg_Type_Bits];
    wire spi_msgResp = spi_msgType[`Msg_Type_Resp_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_dataInReg[`Msg_Arg_Bits];
    reg[`RegWidth2(MsgCycleCount,RespCycleCount)-1:0] spi_dataCounter = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    reg[TurnaroundExtraDelay-1:0] spi_dataInDelayed = 0;
    reg spi_dataOut = 0;
    reg spi_dataOutEn = 0;
    wire spi_dataIn;
    
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
            spi_resp <= spi_resp<<1|1'b0;
            spi_dataOut <= `LeftBit(spi_resp, 0);
            
            case (spi_state)
            SPI_State_MsgIn: begin
                // Wait for the start of the message, signified by the first high bit
                if (spi_dataIn) begin
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
                spi_state <= (spi_msgResp ? SPI_State_RespOut : SPI_State_MsgIn);
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
                
                // Set SD clock source
                `Msg_Type_SDInit: begin
                    $display("[SPI] Got Msg_Type_SDInit: delay=%0d speed=%0d trigger=%0d en=%0d",
                        spi_msgArg[`Msg_Arg_SDInit_Clk_Delay_Bits],
                        spi_msgArg[`Msg_Arg_SDInit_Clk_Speed_Bits],
                        spi_msgArg[`Msg_Arg_SDInit_Trigger_Bits],
                        spi_msgArg[`Msg_Arg_SDInit_En_Bits],
                    );
                    
                    // We don't need to synchronize `sd_clk_delay` into the sd_ domain,
                    // because it should only be set while the sd_ clock is disabled.
                    sd_init_clk_delay <= spi_msgArg[`Msg_Arg_SDInit_Clk_Delay_Bits];
                    
                    case (spi_msgArg[`Msg_Arg_SDInit_Clk_Speed_Bits])
                    `Msg_Arg_SDInit_Clk_Speed_Off:  sd_init_clk_speed <= `SDController_Init_Clk_Speed_Off;
                    `Msg_Arg_SDInit_Clk_Speed_Slow: sd_init_clk_speed <= `SDController_Init_Clk_Speed_Slow;
                    `Msg_Arg_SDInit_Clk_Speed_Fast: sd_init_clk_speed <= `SDController_Init_Clk_Speed_Fast;
                    endcase
                    
                    if (spi_msgArg[`Msg_Arg_SDInit_Trigger_Bits]) begin
                        sd_init_trigger <= !sd_init_trigger;
                    end
                    
                    sd_init_en_ <= !spi_msgArg[`Msg_Arg_SDInit_En_Bits];
                end

                // Clock out SD command
                `Msg_Type_SDSendCmd: begin
                    $display("[SPI] Got Msg_Type_SDSendCmd [respType:%0b]", spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]);
                    // Reset spi_sdCmdDone_ / spi_sdRespDone_ / spi_sdDatInDone_
                    if (!spi_sdCmdDone_) spi_sdCmdDoneAck <= !spi_sdCmdDoneAck;
                    
                    if (!spi_sdRespDone_ && spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]!==`Msg_Arg_SDSendCmd_RespType_None)
                        spi_sdRespDoneAck <= !spi_sdRespDoneAck;
                    
                    if (!spi_sdDatInDone_ && spi_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits]!==`Msg_Arg_SDSendCmd_DatInType_None)
                        spi_sdDatInDoneAck <= !spi_sdDatInDoneAck;
                    
                    case (spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits])
                    `Msg_Arg_SDSendCmd_RespType_None:   sd_cmd_respType <= `SDController_RespType_None;
                    `Msg_Arg_SDSendCmd_RespType_48:     sd_cmd_respType <= `SDController_RespType_48;
                    `Msg_Arg_SDSendCmd_RespType_136:    sd_cmd_respType <= `SDController_RespType_136;
                    endcase
                    
                    case (spi_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits])
                    `Msg_Arg_SDSendCmd_DatInType_None:  sd_cmd_datInType <= `SDController_DatInType_None;
                    `Msg_Arg_SDSendCmd_DatInType_512:   sd_cmd_datInType <= `SDController_DatInType_512;
                    endcase
                    
                    sd_cmd_data <= spi_msgArg[`Msg_Arg_SDSendCmd_CmdData_Bits];
                    sd_cmd_trigger <= !sd_cmd_trigger;
                end
                
                // Get SD status / response
                `Msg_Type_SDStatus: begin
                    $display("[SPI] Got Msg_Type_SDStatus");
                    spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits] <= !spi_sdCmdDone_;
                    spi_resp[`Resp_Arg_SDStatus_RespDone_Bits] <= !spi_sdRespDone_;
                        spi_resp[`Resp_Arg_SDStatus_RespCRCErr_Bits] <= sd_resp_crcErr;
                    spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits] <= !spi_sdDatOutDone_;
                        spi_resp[`Resp_Arg_SDStatus_DatOutCRCErr_Bits] <= sd_datOut_crcErr;
                    spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits] <= !spi_sdDatInDone_;
                        spi_resp[`Resp_Arg_SDStatus_DatInCRCErr_Bits] <= sd_datIn_crcErr;
                        spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits] <= sd_datIn_cmd6AccessMode;
                    spi_resp[`Resp_Arg_SDStatus_Dat0Idle_Bits] <= spi_sdDat0Idle;
                    spi_resp[`Resp_Arg_SDStatus_Resp_Bits] <= sd_resp_data;
                end
                
                `Msg_Type_ImgReset: begin
                    $display("[SPI] Got Msg_Type_ImgReset (rst=%b)", spi_msgArg[`Msg_Arg_ImgReset_Val_Bits]);
                    img_rst_ <= spi_msgArg[`Msg_Arg_ImgReset_Val_Bits];
                end
                
                `Msg_Type_ImgCapture: begin
                    $display("[SPI] Got Msg_Type_ImgCapture (block=%b)", spi_msgArg[`Msg_Arg_ImgCapture_DstBlock_Bits]);
                    // Reset spi_imgCaptureDone_
                    if (!spi_imgCaptureDone_) spi_imgCaptureDoneAck <= !spi_imgCaptureDoneAck;
                    imgctrl_cmd_ramBlock <= spi_msgArg[`Msg_Arg_ImgCapture_DstBlock_Bits];
                    imgctrl_cmd_capture <= !imgctrl_cmd_capture;
                end
                
                `Msg_Type_ImgCaptureStatus: begin
                    $display("[SPI] Got Msg_Type_ImgCaptureStatus");
                    spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits] <= !spi_imgCaptureDone_;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ImageWidth_Bits] <= imgctrl_status_captureImageWidth;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ImageHeight_Bits] <= imgctrl_status_captureImageHeight;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits] <= imgctrl_status_captureHighlightCount;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits] <= imgctrl_status_captureShadowCount;
                    spi_resp[2:0] <= 3'b101; // TODO: remove
                end
                
                // `Msg_Type_ImgReadout: begin
                //     // $display("[SPI] Got Msg_Type_ImgReadout");
                //     // // Reset `spi_imgReadoutStarted` if it's asserted
                //     // if (spi_imgReadoutStarted) spi_imgReadoutStartedAck <= !spi_imgReadoutStartedAck;
                //     //
                //     // spi_imgReadoutCounter <= spi_msgArg[`Msg_Arg_ImgReadout_Counter_Bits];
                //     // spi_imgReadoutCaptureNext <= spi_msgArg[`Msg_Arg_ImgReadout_CaptureNext_Bits];
                //     // spi_imgReadoutDone <= 0;
                //     // spi_state <= SPI_State_ImgOut;
                // end
                
                `Msg_Type_ImgReadout: begin
                    $display("[SPI] Got Msg_Type_ImgReadout");
                    // Reset spi_sdDatOutDone_
                    if (!spi_sdDatOutDone_) spi_sdDatOutDoneAck <= !spi_sdDatOutDoneAck;
                    // Start SD DatOut
                    sd_datOut_start <= !sd_datOut_start;
                end
                
                `Msg_Type_ImgI2CTransaction: begin
                    $display("[SPI] Got Msg_Type_ImgI2CTransaction");
                    
                    // Reset `spi_imgi2c_done_` if it's asserted
                    if (!spi_imgi2c_done_) spi_imgi2c_doneAck <= !spi_imgi2c_doneAck;
                    
                    imgi2c_cmd_write <= spi_msgArg[`Msg_Arg_ImgI2CTransaction_Write_Bits];
                    imgi2c_cmd_regAddr <= spi_msgArg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits];
                    imgi2c_cmd_dataLen <= (spi_msgArg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits]===`Msg_Arg_ImgI2CTransaction_DataLen_2);
                    imgi2c_cmd_writeData <= spi_msgArg[`Msg_Arg_ImgI2CTransaction_WriteData_Bits];
                    imgi2c_cmd_trigger <= !imgi2c_cmd_trigger;
                end
                
                `Msg_Type_ImgI2CStatus: begin
                    $display("[SPI] Got Msg_Type_ImgI2CStatus done_:%0d err:%0d readData:0x%x)",
                        spi_imgi2c_done_,
                        imgi2c_status_err,
                        imgi2c_status_readData
                    );
                    spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits] <= !spi_imgi2c_done_;
                    spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits] <= imgi2c_status_err;
                    spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits] <= imgi2c_status_readData;
                end
                
                `Msg_Type_Nop: begin
                    $display("[SPI] Got Msg_Type_None");
                end
                
                default: begin
                    $display("[SPI] BAD COMMAND: %0d ❌", spi_msgType);
                    `Finish;
                end
                endcase
            end
            
            SPI_State_RespOut: begin
                if (spi_dataCounter) begin
                    spi_dataOutEn <= 1;
                end else begin
                    spi_state <= SPI_State_MsgIn;
                end
            end
            endcase
        end
    end
    
    
    // ====================
    // Pin: ice_msp_spi_clk
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b0000_01) // Output: none; input: unregistered
    ) SB_IO_ice_msp_spi_clk (
        .PACKAGE_PIN(ice_msp_spi_clk),
        .D_IN_0(spi_clk)
    );
    
    // ====================
    // Pin: ice_msp_spi_data
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1010_01) // Output: tristate; input: unregistered
    ) SB_IO_ice_msp_spi_data (
        .PACKAGE_PIN(ice_msp_spi_data),
        .OUTPUT_ENABLE(spi_dataOutEn),
        .D_OUT_0(spi_dataOut),
        .D_IN_0(spi_dataIn)
    );
    
`ifdef SIM
    // Sim workaround: for some reason `spi_dataOut` has to be assigned to something non-0
    // before it will drive a 0, otherwise it drives an x.
    initial begin
        spi_dataOut = 1'bz;
        spi_dataOut = 1'b0;
    end
`endif
    
    // // TODO: ideally we'd use the SB_IO definition below for `ice_msp_spi_data`, but we can't because
    // // TODO: Rev4's `ice_msp_spi_data` net (pin K1), is a PIO pair with `ram_dq[15]` (pin J1), which
    // // TODO: means they both have to use the same clock.
    // // TODO: since ice_msp_spi_data is relatively low speed (16 MHz), for now we just won't register it.
    // SB_IO #(
    //     .PIN_TYPE(6'b1101_00)
    // ) SB_IO_ice_msp_spi_data (
    //     .INPUT_CLK(spi_clk),
    //     .OUTPUT_CLK(spi_clk),
    //     .PACKAGE_PIN(ice_msp_spi_data),
    //     .OUTPUT_ENABLE(spi_dataOutEn),
    //     .D_OUT_0(spi_dataOut),
    //     .D_IN_0(spi_dataIn)
    // );
    
endmodule







`ifdef SIM
module Testbench();
    reg ice_img_clk16mhz = 0;
    reg ice_msp_spi_clk = 0;
    wire ice_msp_spi_data;
    
    wire sd_clk;
    wire sd_cmd;
    wire[3:0] sd_dat;
    
    wire        img_dclk;
    wire[11:0]  img_d;
    wire        img_fv;
    wire        img_lv;
    wire        img_rst_;
    wire        img_sclk;
    tri1        img_sdata;
    
    wire        ram_clk;
    wire        ram_cke;
    wire[1:0]   ram_ba;
    wire[11:0]  ram_a;
    wire        ram_cs_;
    wire        ram_ras_;
    wire        ram_cas_;
    wire        ram_we_;
    wire[1:0]   ram_dqm;
    wire[15:0]  ram_dq;
    
    wire[3:0] ice_led;
    wire sim_rst_;
    
    initial begin
        forever begin
            ice_img_clk16mhz = ~ice_img_clk16mhz;
            #32;
        end
    end
    
    Top Top(.*);
    
    SDCardSim SDCardSim(
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    localparam ImageWidth = 64;
    localparam ImageHeight = 32;
    ImgSim #(
        .ImageWidth(ImageWidth),
        .ImageHeight(ImageHeight)
    ) ImgSim (
        .img_dclk(img_dclk),
        .img_d(img_d),
        .img_fv(img_fv),
        .img_lv(img_lv),
        .img_rst_(img_rst_)
    );
    
    ImgI2CSlaveSim ImgI2CSlaveSim(
        .i2c_clk(img_sclk),
        .i2c_data(img_sdata)
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
    
    reg[`Msg_Len-1:0] spi_dataOutReg = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    
    reg spi_dataOutEn = 0;    
    wire spi_dataIn = ice_msp_spi_data;
    assign ice_msp_spi_data = (spi_dataOutEn ? `LeftBit(spi_dataOutReg, 0) : 1'bz);
    
    localparam ice_msp_spi_clk_HALF_PERIOD = 32; // 16 MHz
    // localparam ice_msp_spi_clk_HALF_PERIOD = 64; // 8 MHz
    // localparam ice_msp_spi_clk_HALF_PERIOD = 1024; // 1 MHz
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
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
        
        // Clock in response (if one is sent for this type of message)
        if (typ[`Msg_Type_Resp_Bits]) begin
            for (i=0; i<`Resp_Len; i++) begin
                #(ice_msp_spi_clk_HALF_PERIOD);
                ice_msp_spi_clk = 1;
            
                    spi_resp = spi_resp<<1|spi_dataIn;
            
                #(ice_msp_spi_clk_HALF_PERIOD);
                ice_msp_spi_clk = 0;
            end
        end
        
        // Give some down time to prevent the SPI state machine from resetting.
        // This can happen if the SPI master (this testbench) delivers clocks
        // at the same frequency as spirst_clk. In that case, it's possible
        // for the reset logic to always observe the SPI clock as being high
        // (even though it's toggling), and trigger a reset.
        #128;
    end endtask
    
    task TestRst; begin
        $display("\n[Testbench] ========== TestRst ==========");
        
        $display("[Testbench] ice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #20000;
        
        if (sim_rst_ === 1'b1) begin
            $display("[Testbench] sim_rst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b1 ❌ (%b)", sim_rst_);
            `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 1");
        ice_msp_spi_clk = 1;
        #20000;
        
        if (sim_rst_ === 1'b0) begin
            $display("[Testbench] sim_rst_ === 1'b0 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b0 ❌ (%b)", sim_rst_);
            `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #20000;
        
        if (sim_rst_ === 1'b1) begin
            $display("[Testbench] sim_rst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b1 ❌ (%b)", sim_rst_);
            `Finish;
        end
    end endtask
    
    task TestNop; begin
        $display("\n[Testbench] ========== TestNop ==========");
        SendMsg(`Msg_Type_Nop, 56'h00000000000000);
    end endtask
    
    task TestEcho(input[`Msg_Arg_Echo_Msg_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[Testbench] ========== TestEcho ==========");
        arg[`Msg_Arg_Echo_Msg_Bits] = val;
        
        SendMsg(`Msg_Type_Echo, arg);
        if (spi_resp[`Resp_Arg_Echo_Msg_Bits] === val) begin
            $display("[Testbench] Response OK: %h ✅", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
        end else begin
            $display("[Testbench] Bad response: %h ❌", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
            `Finish;
        end
    end endtask
    
    task TestLEDSet(input[`Msg_Arg_LEDSet_Val_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[Testbench] ========== TestLEDSet ==========");
        arg = 0;
        arg[`Msg_Arg_LEDSet_Val_Bits] = val;
        
        SendMsg(`Msg_Type_LEDSet, arg);
        if (ice_led === val) begin
            $display("[Testbench] ice_led matches (%b) ✅", ice_led);
        end else begin
            $display("[Testbench] ice_led doesn't match (expected: %b, got: %b) ❌", val, ice_led);
            `Finish;
        end
    end endtask
    
    
    
    
    
    
    
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
        for (i=0; i<100 && !done; i++) begin
            // Request SD status
            SendMsg(`Msg_Type_SDStatus, 0);
            // We're done when the SD command is sent
            done = spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits];
            // If a response is expected, we're done when the response is received
            if (respType !== `Msg_Arg_SDSendCmd_RespType_None) done &= spi_resp[`Resp_Arg_SDStatus_RespDone_Bits];
            if (datInType !== `Msg_Arg_SDSendCmd_DatInType_None) done &= spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits];
            
            // // Our clock is much faster than the SD slow clock (16 MHz vs .4 MHz),
            // // so wait a bit before asking for the status again
            // #(50_000);
        end
        
        if (!done) begin
            $display("[Testbench] SD card response timeout ❌");
            `Finish;
        end
    end endtask
    
    task TestSDConfig(
        input[`Msg_Arg_SDInit_Clk_Delay_Len-1:0] delay,
        input[`Msg_Arg_SDInit_Clk_Speed_Len-1:0] speed,
        input[`Msg_Arg_SDInit_Trigger_Len-1:0] trigger,
        input[`Msg_Arg_SDInit_En_Len-1:0] en
    ); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        // $display("\n[Testbench] ========== TestSDConfig ==========");
        arg[`Msg_Arg_SDInit_Clk_Delay_Bits] = delay;
        arg[`Msg_Arg_SDInit_Clk_Speed_Bits] = speed;
        arg[`Msg_Arg_SDInit_Trigger_Bits] = trigger;
        arg[`Msg_Arg_SDInit_En_Bits] = en;
        
        SendMsg(`Msg_Type_SDInit, arg);
    end endtask
    
    task TestSDInit; begin
        reg[15:0] i;
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;
        
        $display("\n[Testbench] ========== TestSDInit ==========");
        
        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Off,  0, 1); // Clock=off,  InitMode=enabled
        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 0, 1); // Clock=slow, InitMode=enabled
        // <-- Turn on power to SD card
        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 1, 1); // InitMode=enabled,trigger
        
`ifdef SDCARDSIM_LVS_INIT_IGNORE_5MS
        // Wait 50us, because waiting 5ms takes forever in simulation
        $display("[Testbench] Waiting 50us (and pretending it's 5ms)...");
        #(50_000);
`else
        // Wait 5ms
        $display("[Testbench] Waiting 5ms...");
        #(5_000_000);
`endif
        $display("[Testbench] 5ms elapsed");
        
        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 0, 0); // InitMode=disabled
        
        // // Wait for SD init to be complete
        // done = 0;
        // for (i=0; i<10 && !done; i++) begin
        //     // Request SD status
        //     SendMsg(`Msg_Type_SDStatus, 0);
        //     // We're done when the `InitDone` bit is set
        //     done = spi_resp[`Resp_Arg_SDStatus_InitDone_Bits];
        // end
        
        $display("[Testbench] Init done ✅");
    end endtask
    
    task TestSDCMD0; begin
        // ====================
        // Test SD CMD0 (GO_IDLE)
        // ====================
        $display("\n[Testbench] ========== TestSDCMD0 ==========");
        SendSDCmdResp(CMD0, `Msg_Arg_SDSendCmd_RespType_None, `Msg_Arg_SDSendCmd_DatInType_None, 0);
    end endtask
    
    task TestSDCMD8; begin
        // ====================
        // Test SD CMD8 (SEND_IF_COND)
        // ====================
        reg[`Resp_Arg_SDStatus_Resp_Len-1:0] sdResp;
        
        $display("\n[Testbench] ========== TestSDCMD8 ==========");
        
        // Send SD CMD8
        SendSDCmdResp(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'h000001AA);
        if (spi_resp[`Resp_Arg_SDStatus_RespCRCErr_Bits] !== 1'b0) begin
            $display("[Testbench] CRC error ❌");
            `Finish;
        end

        sdResp = spi_resp[`Resp_Arg_SDStatus_Resp_Bits];
        if (sdResp[15:8] !== 8'hAA) begin
            $display("[Testbench] Bad response: %h ❌", spi_resp);
            `Finish;
        end
    end endtask
    
    task TestSDDatOut; begin
        // ====================
        // Test writing data to SD card / DatOut
        // ====================
        
        $display("\n========== TestSDDatOut ==========");
        
        // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        SendSDCmdResp(CMD55, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
        SendSDCmdResp(ACMD23, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b1);
        
        // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        SendSDCmdResp(CMD25, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
        
        // Clock out data on DAT lines
        TestImgReadout();
        
        // Wait until we're done clocking out data on DAT lines
        $display("[Testbench] Waiting while data is written...");
        do begin
            // Request SD status
            SendMsg(`Msg_Type_SDStatus, 0);
        end while(!spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits]);
        $display("[Testbench] Done writing (SD resp: %b)", spi_resp[`Resp_Arg_SDStatus_Resp_Bits]);
        
        // Check CRC status
        if (spi_resp[`Resp_Arg_SDStatus_DatOutCRCErr_Bits] === 1'b0) begin
            $display("[Testbench] DatOut CRC OK ✅");
        end else begin
            $display("[Testbench] DatOut CRC bad ❌");
            `Finish;
        end
        
        // Stop transmission
        SendSDCmdResp(CMD12, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
    end endtask

    task TestSDDatIn; begin
        // ====================
        // Test CMD6 (SWITCH_FUNC) + DatIn
        // ====================
        
        $display("\n[Testbench] ========== TestSDDatIn ==========");
        
        // Send SD command CMD6 (SWITCH_FUNC)
        SendSDCmdResp(CMD6, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 32'h80FFFFF3);
        $display("[Testbench] Waiting for DatIn to complete...");
        do begin
            // Request SD status
            SendMsg(`Msg_Type_SDStatus, 0);
        end while(!spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);
        $display("[Testbench] DatIn completed");

        // Check DatIn CRC status
        if (spi_resp[`Resp_Arg_SDStatus_DatInCRCErr_Bits] === 1'b0) begin
            $display("[Testbench] DatIn CRC OK ✅");
        end else begin
            $display("[Testbench] DatIn CRC bad ❌");
            `Finish;
        end
        
        // Check the access mode from the CMD6 response
        if (spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits] === 4'h3) begin
            $display("[Testbench] CMD6 access mode == 0x3 ✅");
        end else begin
            $display("[Testbench] CMD6 access mode == 0x%h ❌", spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits]);
            `Finish;
        end
    end endtask
    
    task TestSDCMD2; begin
        // ====================
        // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
        //   Note: we expect CRC errors in the response because the R2
        //   response CRC doesn't follow the semantics of other responses
        // ====================
        
        $display("\n[Testbench] ========== TestSDCMD2 ==========");
        
        // Send SD command CMD2 (ALL_SEND_CID)
        SendSDCmdResp(CMD2, `Msg_Arg_SDSendCmd_RespType_136, `Msg_Arg_SDSendCmd_DatInType_None, 0);
        $display("[Testbench] ====================================================");
        $display("[Testbench] ^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        $display("[Testbench] ====================================================");
    end endtask
    
    task TestSDRespRecovery; begin
        reg done;
        reg[15:0] i;
        
        $display("\n[Testbench] ========== TestSDRespRecovery ==========");
        
        // Send an SD command that doesn't provide a response
        SendSDCmd(CMD0, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 0);
        $display("[Testbench] Verifying that Resp times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsg(`Msg_Type_SDStatus, 0);
            $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);
            
            done = spi_resp[`Resp_Arg_SDStatus_RespDone_Bits];
        end
        
        if (!done) begin
            $display("[Testbench] Resp timeout ✅");
            $display("[Testbench] Testing Resp after timeout...");
            TestSDCMD8();
            $display("[Testbench] Resp Recovered ✅");
        
        end else begin
            $display("[Testbench] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask

    // task TestSDDatOutRecovery; begin
    //     reg done;
    //     reg[15:0] i;
    //
    //     // Clock out data on DAT lines, but without the SD card
    //     // expecting data so that we don't get a response
    //     SendMsg(`Msg_Type_PixReadout, 0);
    //
    //     #50000;
    //
    //     // Verify that we timeout
    //     $display("[Testbench] Verifying that DatOut times out...");
    //     done = 0;
    //     for (i=0; i<10 && !done; i++) begin
    //         SendMsg(`Msg_Type_SDStatus, 0);
    //         $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
    //             i+1,
    //             spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
    //             spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
    //             spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
    //             spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);
    //
    //         done = spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits];
    //     end
    //
    //     if (!done) begin
    //         $display("[Testbench] DatOut timeout ✅");
    //         $display("[Testbench] Testing DatOut after timeout...");
    //         TestSDDatOut();
    //         $display("[Testbench] DatOut Recovered ✅");
    //
    //     end else begin
    //         $display("[Testbench] DatOut didn't timeout? ❌");
    //         `Finish;
    //     end
    // end endtask

    task TestSDDatInRecovery; begin
        reg done;
        reg[15:0] i;
        
        $display("\n[Testbench] ========== TestSDDatInRecovery ==========");
        
        // Send SD command that doesn't respond on the DAT lines,
        // but specify that we expect DAT data
        SendSDCmd(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 0);
        $display("[Testbench] Verifying that DatIn times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsg(`Msg_Type_SDStatus, 0);
            $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);

            done = spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits];
        end

        if (!done) begin
            $display("[Testbench] DatIn timeout ✅");
            $display("[Testbench] Testing DatIn after timeout...");
            TestSDDatIn();
            $display("[Testbench] DatIn Recovered ✅");

        end else begin
            $display("[Testbench] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    
    
    
    
    
    
    
    task TestImgReset; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n========== TestImgReset ==========");
        
        // ====================
        // Test Img reset
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgReset_Val_Bits] = 0;
        SendMsg(`Msg_Type_ImgReset, arg);
        if (img_rst_ === arg[`Msg_Arg_ImgReset_Val_Bits]) begin
            $display("[Testbench] Reset=0 success ✅");
        end else begin
            $display("[Testbench] Reset=0 failed ❌");
            `Finish;
        end
        
        arg = 0;
        arg[`Msg_Arg_ImgReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_ImgReset, arg);
        if (img_rst_ === arg[`Msg_Arg_ImgReset_Val_Bits]) begin
            $display("[Testbench] Reset=1 success ✅");
        end else begin
            $display("[Testbench] Reset=1 failed ❌");
            `Finish;
        end
    end endtask
    
    task TestImgCapture; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n[Testbench] ========== TestImgCapture ==========");
        
        arg = 0;
        arg[`Msg_Arg_ImgCapture_DstBlock_Bits] = 0;
        SendMsg(`Msg_Type_ImgCapture, arg);
        
        // Wait until capture is done
        $display("[Testbench] Waiting until capture is complete...");
        do begin
            // Request Img status
            SendMsg(`Msg_Type_ImgCaptureStatus, 0);
        end while(!spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits]);
        $display("[Testbench] Capture done ✅ (done:%b image size:%0dx%0d, highlightCount:%0d, shadowCount:%0d)",
            spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_ImageWidth_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_ImageHeight_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits],
        );
    end endtask
    
    task TestImgReadout; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n[Testbench] ========== TestImgReadout ==========");
        
        arg = 0;
        SendMsg(`Msg_Type_ImgReadout, arg);
    end endtask
    
    task TestImgI2CWriteRead; begin
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;
        
        // ====================
        // Test ImgI2C Write (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 1;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_2;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h4242;
        arg[`Msg_Arg_ImgI2CTransaction_WriteData_Bits] = 16'hCAFE;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);

        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );

            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end

        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[Testbench] Write success ✅");
        end else begin
            $display("[Testbench] Write failed ❌");
            `Finish;
        end
        
        // ====================
        // Test ImgI2C Read (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_2;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h4242;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[Testbench] Read success ✅");
        end else begin
            $display("[Testbench] Read failed ❌");
            `Finish;
        end
        
        if (spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits] === 16'hCAFE) begin
            $display("[Testbench] Read correct data ✅ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
        end else begin
            $display("[Testbench] Read incorrect data ❌ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
            `Finish;
        end
        
        // ====================
        // Test ImgI2C Write (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 1;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_1;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h8484;
        arg[`Msg_Arg_ImgI2CTransaction_WriteData_Bits] = 16'h0037;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[Testbench] Write success ✅");
        end else begin
            $display("[Testbench] Write failed ❌");
            `Finish;
        end
        
        // ====================
        // Test ImgI2C Read (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_1;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h8484;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);

        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end

        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[Testbench] Read success ✅");
        end else begin
            $display("[Testbench] Read failed ❌");
            `Finish;
        end

        if ((spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF) === 16'h0037) begin
            $display("[Testbench] Read correct data ✅ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
        end else begin
            $display("[Testbench] Read incorrect data ❌ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
            `Finish;
        end
    end endtask
    
    
    
    
    
    
    
    
    
    initial begin
        // Set our initial state
        spi_dataOutReg = 0;
        spi_dataOutEn = 0;
        
        // Pulse the clock to get SB_IO initialized
        ice_msp_spi_clk = 1;
        #1;
        ice_msp_spi_clk = 0;
        
        TestRst();
        TestEcho(56'h00000000000000);
        TestEcho(56'hCAFEBABEFEEDAA);
        TestNop();
        TestEcho(56'hCAFEBABEFEEDAA);
        TestLEDSet(4'b1010);
        TestLEDSet(4'b0101);
        TestEcho(56'h123456789ABCDE);
        TestNop();
        TestRst();
        
        // Do Img stuff before SD stuff, so that an image is ready for readout to the SD card
        TestImgReset();
        // TestImgI2CWriteRead();
        TestImgCapture();
        
        TestSDInit();
        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Off, 0, 0);
        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Fast, 0, 0);
        TestSDCMD0();
        TestSDCMD8();
        TestSDDatOut();
        // TestSDCMD2();
        // TestSDDatIn();
        // TestSDRespRecovery();
        // // TestSDDatOutRecovery();
        // TestSDDatInRecovery();
        
        `Finish;
    end
endmodule
`endif
