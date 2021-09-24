`include "Util.v"
`include "Sync.v"
`include "ToggleAck.v"
`include "SDController.v"
`include "ICEAppTypes.v"
`include "ClockGen.v"
`include "ImgController.v"
`include "ImgI2CMaster.v"
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
    reg                                                 imgctrl_cmd_capture = 0;
    reg                                                 imgctrl_cmd_readout = 0;
    reg[0:0]                                            imgctrl_cmd_ramBlock = 0;
    reg[127:0]                                          imgctrl_cmd_header = 0;
    wire                                                imgctrl_readout_clk;
    wire                                                imgctrl_readout_start;
    wire                                                imgctrl_readout_ready;
    wire                                                imgctrl_readout_trigger;
    wire[15:0]                                          imgctrl_readout_data;
    wire                                                imgctrl_status_captureDone;
    wire[`RegWidth(ImageSizeMax)-1:0]                   imgctrl_status_captureWordCount;
    wire[17:0]                                          imgctrl_status_captureHighlightCount;
    wire[17:0]                                          imgctrl_status_captureShadowCount;
    ImgController #(
        .ClkFreq(Img_Clk_Freq),
        .ImageSizeMax(ImageSizeMax),
        .HeaderWordCount(ImageHeaderWordCount)
    ) ImgController (
        .clk(img_clk),
        
        .cmd_capture(imgctrl_cmd_capture),
        .cmd_readout(imgctrl_cmd_readout),
        .cmd_ramBlock(imgctrl_cmd_ramBlock),
        .cmd_header(imgctrl_cmd_header),
        
        .readout_clk(imgctrl_readout_clk),
        .readout_start(imgctrl_readout_start),
        .readout_ready(imgctrl_readout_ready),
        .readout_trigger(imgctrl_readout_trigger),
        .readout_data(imgctrl_readout_data),
        
        .status_captureDone(imgctrl_status_captureDone),
        .status_captureWordCount(imgctrl_status_captureWordCount),
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
    reg         sd_init_reset           = 0;
    reg         sd_init_trigger         = 0;
    reg[1:0]    sd_init_clkSpeed        = 0;
    reg[3:0]    sd_init_clkDelay        = 0;
    reg         sd_cmd_trigger          = 0;
    reg[47:0]   sd_cmd_data             = 0;
    reg[1:0]    sd_cmd_respType         = 0;
    reg[1:0]    sd_cmd_datInType        = 0;
    wire        sd_cmd_done;
    wire        sd_resp_done;
    wire[47:0]  sd_resp_data;
    wire        sd_resp_crcErr;
    reg         sd_datOut_stop          = 0;
    wire        sd_datOut_stopped;
    wire        sd_datOut_start;
    wire        sd_datOut_ready;
    wire        sd_datOut_done;
    wire        sd_datOut_crcErr;
    wire        sd_datOutRead_clk;
    wire        sd_datOutRead_ready;
    wire        sd_datOutRead_trigger;
    wire[15:0]  sd_datOutRead_data;
    wire        sd_datIn_done;
    wire        sd_datIn_crcErr;
    wire        sd_datInWrite_rst_;
    wire        sd_datInWrite_clk;
    wire        sd_datInWrite_ready;
    wire        sd_datInWrite_trigger;
    wire[15:0]  sd_datInWrite_data;
    wire        sd_status_dat0Idle;
    
    SDController #(
        .ClkFreq(SD_Clk_Freq)
    ) SDController (
        .clk(sd_clk_int),
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat),
        
        .init_reset(sd_init_reset),
        .init_trigger(sd_init_trigger),
        .init_clkSpeed(sd_init_clkSpeed),
        .init_clkDelay(sd_init_clkDelay),
        
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
        
        .datInWrite_rst_(sd_datInWrite_rst_),
        .datInWrite_clk(sd_datInWrite_clk),
        .datInWrite_ready(sd_datInWrite_ready),
        .datInWrite_trigger(sd_datInWrite_trigger),
        .datInWrite_data(sd_datInWrite_data),
        
        .status_dat0Idle(sd_status_dat0Idle)
    );
    
    // Connect imgctrl_readout_* to sd_datOutRead_*
    assign imgctrl_readout_clk = sd_datOutRead_clk;
    assign sd_datOut_start = imgctrl_readout_start;
    assign sd_datOutRead_ready = imgctrl_readout_ready;
    assign imgctrl_readout_trigger = sd_datOutRead_trigger;
    assign sd_datOutRead_data = imgctrl_readout_data;
    
    // ====================
    // CMD6 Access Mode Capture
    // ====================
    assign sd_datInWrite_ready = 1;
    reg[`RegWidth((512/16)-1)-1:0] sdcmd6_counter = 0;
    reg[3:0] sdcmd6_accessMode = 0;
    always @(posedge sd_datInWrite_clk, negedge sd_datInWrite_rst_) begin
        if (!sd_datInWrite_rst_) begin
            sdcmd6_counter <= ~0;
        
        end else begin
            if (sd_datInWrite_trigger) begin
                sdcmd6_counter <= sdcmd6_counter-1;
                
                if (sdcmd6_counter === 23) begin
                    sdcmd6_accessMode <= sd_datInWrite_data[11:8];
                    $display("sdcmd6_accessMode: %h", sd_datInWrite_data[11:8]);
                end
            end
        end
    end
    
    
    
    
    
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
                // Verify that we never get a clock while spi_dataIn is undriven (z) / invalid (x)
                if (spi_dataIn!==1'b0 && spi_dataIn!==1'b1) begin
                    $display("spi_dataIn invalid: %b ❌", spi_dataIn);
                    #1000;
                    `Finish;
                end
                
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
                spi_state <= SPI_State_RespOut;
                spi_dataCounter <= (spi_msgResp ? RespCycleCount : 0);
                
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
                    $display("[SPI] Got Msg_Type_SDInit: delay=%0d speed=%0d trigger=%b reset=%b",
                        spi_msgArg[`Msg_Arg_SDInit_Clk_Delay_Bits],
                        spi_msgArg[`Msg_Arg_SDInit_Clk_Speed_Bits],
                        spi_msgArg[`Msg_Arg_SDInit_Trigger_Bits],
                        spi_msgArg[`Msg_Arg_SDInit_Reset_Bits],
                    );
                    
                    // We don't need to synchronize `sd_clk_delay` into the sd_ domain,
                    // because it should only be set while the sd_ clock is disabled.
                    sd_init_clkDelay <= spi_msgArg[`Msg_Arg_SDInit_Clk_Delay_Bits];
                    
                    sd_init_clkSpeed <= spi_msgArg[`Msg_Arg_SDInit_Clk_Speed_Bits];
                    
                    if (spi_msgArg[`Msg_Arg_SDInit_Trigger_Bits]) begin
                        sd_init_trigger <= !sd_init_trigger;
                    end
                    
                    if (spi_msgArg[`Msg_Arg_SDInit_Reset_Bits]) begin
                        sd_init_reset <= !sd_init_reset;
                    end
                end
                
                // Clock out SD command
                `Msg_Type_SDSendCmd: begin
                    $display("[SPI] Got Msg_Type_SDSendCmd [respType:%0b]", spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]);
                    // Reset spi_sdCmdDone_ / spi_sdRespDone_ / spi_sdDatInDone_
                    if (!spi_sdCmdDone_) spi_sdCmdDoneAck <= !spi_sdCmdDoneAck;
                    
                    if (!spi_sdRespDone_ && spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]!==`SDController_RespType_None)
                        spi_sdRespDoneAck <= !spi_sdRespDoneAck;
                    
                    if (!spi_sdDatInDone_ && spi_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits]!==`SDController_DatInType_None)
                        spi_sdDatInDoneAck <= !spi_sdDatInDoneAck;
                    
                    sd_cmd_respType <= spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits];
                    sd_cmd_datInType <= spi_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits];
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
                        spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits] <= sdcmd6_accessMode;
                    spi_resp[`Resp_Arg_SDStatus_Dat0Idle_Bits] <= spi_sdDat0Idle;
                    spi_resp[`Resp_Arg_SDStatus_Resp_Bits] <= sd_resp_data;
                end
                
                `Msg_Type_ImgReset: begin
                    $display("[SPI] Got Msg_Type_ImgReset (rst=%b)", spi_msgArg[`Msg_Arg_ImgReset_Val_Bits]);
                    img_rst_ <= spi_msgArg[`Msg_Arg_ImgReset_Val_Bits];
                end
                
                `Msg_Type_ImgSetHeader1: begin
                    $display("[SPI] Got Msg_Type_ImgSetHeader1 (header1=%x)", spi_msgArg[`Msg_Arg_ImgSetHeader1_Header_Bits]);
                    imgctrl_cmd_header[127:72] <= spi_msgArg[`Msg_Arg_ImgSetHeader1_Header_Bits];
                end
                
                `Msg_Type_ImgSetHeader2: begin
                    $display("[SPI] Got Msg_Type_ImgSetHeader2 (header2=%x)", spi_msgArg[`Msg_Arg_ImgSetHeader2_Header_Bits]);
                    imgctrl_cmd_header[71:16] <= spi_msgArg[`Msg_Arg_ImgSetHeader2_Header_Bits];
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
                    spi_resp[`Resp_Arg_ImgCaptureStatus_WordCount_Bits] <= imgctrl_status_captureWordCount;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits] <= imgctrl_status_captureHighlightCount;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits] <= imgctrl_status_captureShadowCount;
                end
                
                `Msg_Type_ImgReadout: begin
                    $display("[SPI] Got Msg_Type_ImgReadout");
                    // Reset spi_sdDatOutDone_
                    if (!spi_sdDatOutDone_) spi_sdDatOutDoneAck <= !spi_sdDatOutDoneAck;
                    imgctrl_cmd_ramBlock <= spi_msgArg[`Msg_Arg_ImgReadout_DstBlock_Bits];
                    imgctrl_cmd_readout <= !imgctrl_cmd_readout;
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
