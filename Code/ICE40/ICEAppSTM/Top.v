`include "Util.v"
`include "ICEAppTypes.v"
`include "TogglePulse.v"
`include "ClockGen.v"
`include "AFIFOChain.v"
`include "SDController.v"
`include "ToggleAck.v"
`include "Sync.v"
`include "ImgController.v"
`include "ImgI2CMaster.v"
`timescale 1ns/1ps

// TODO: have consistent ordering for FIFO ports for: AFIFO, AFIFOChain, SDController, ImgController
//       clk, trigger, data, ready

// TODO: try to make width of SDController data nets a parameter (4, 8, 16, ...), so that ICEAppSTM can use width=8 to read, but ICEAppMSP can use width=16 to write

module Top(
    input wire          ice_img_clk16mhz,
    
    // STM SPI port
    input wire          ice_st_spi_clk,
    input wire          ice_st_spi_cs_,
    inout wire[7:0]     ice_st_spi_d,
    output wire         ice_st_spi_d_ready,
    output wire         ice_st_spi_d_ready_rev4bodge,
    
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
);
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
    reg                                 imgctrl_cmd_readout = 0;
    reg[0:0]                            imgctrl_cmd_ramBlock = 0;
    reg[ImageHeaderWordCount*16-1:0]    imgctrl_cmd_header = 0;
    wire                                imgctrl_readout_clk;
    wire                                imgctrl_readout_start;
    wire                                imgctrl_readout_ready;
    wire                                imgctrl_readout_trigger;
    wire[15:0]                          imgctrl_readout_data;
    wire                                imgctrl_status_captureDone;
    wire[`RegWidth(ImageSizeMax)-1:0]   imgctrl_status_captureWordCount;
    wire[17:0]                          imgctrl_status_captureHighlightCount;
    wire[17:0]                          imgctrl_status_captureShadowCount;
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
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // ====================
    // AFIFOChain
    // ====================
    localparam AFIFOChainCount = 8; // 4096*8=32768 bits=4096 bytes total, readable in chunks of 2048
    
    wire        fifo_rst_;
    wire        fifo_prop_clk;
    wire        fifo_prop_w_ready;
    wire        fifo_prop_r_ready;
    wire        fifo_w_clk;
    wire        fifo_w_trigger;
    wire[15:0]  fifo_w_data;
    wire        fifo_w_ready;
    wire        fifo_r_clk;
    reg         fifo_r_trigger      = 0;
    wire[15:0]  fifo_r_data;
    wire        fifo_r_ready;
    
    AFIFOChain #(
        .W(16),
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
    
    assign fifo_prop_clk    = fifo_w_clk;
    assign fifo_r_clk       = ice_st_spi_clk;
    
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
    reg         sd_datOut_trigger       = 0;
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
        
        .datOut_trigger(sd_datOut_trigger),
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
    
    assign fifo_rst_            = sd_datInWrite_rst_;
    assign fifo_w_clk           = sd_datInWrite_clk;
    assign fifo_w_trigger       = sd_datInWrite_trigger;
    assign fifo_w_data          = sd_datInWrite_data;
    assign sd_datInWrite_ready  = fifo_w_ready;
    
    // ====================
    // SPI State Machine
    // ====================
    
    // SD nets
    `ToggleAck(spi_sdCmdDone_, spi_sdCmdDoneAck, sd_cmd_done, posedge, ice_st_spi_clk);
    `ToggleAck(spi_sdRespDone_, spi_sdRespDoneAck, sd_resp_done, posedge, ice_st_spi_clk);
    `Sync(spi_sdDatOutDone, sd_datOut_done, posedge, ice_st_spi_clk);
    `ToggleAck(spi_sdDatInDone_, spi_sdDatInDoneAck, sd_datIn_done, posedge, ice_st_spi_clk);
    `Sync(spi_sdDat0Idle, sd_status_dat0Idle, posedge, ice_st_spi_clk);
    
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
    localparam SPI_State_SDReadout  = 4;    // +1
    localparam SPI_State_Nop        = 6;    // +0
    localparam SPI_State_Count      = 7;
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
                    spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits] <= spi_sdDatOutDone;
                        spi_resp[`Resp_Arg_SDStatus_DatOutCRCErr_Bits] <= sd_datOut_crcErr;
                    spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits] <= !spi_sdDatInDone_;
                        spi_resp[`Resp_Arg_SDStatus_DatInCRCErr_Bits] <= sd_datIn_crcErr;
                        spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits] <= 4'bxxxx; // TODO: how do we handle CMD6AccessMode?
                    spi_resp[`Resp_Arg_SDStatus_Dat0Idle_Bits] <= spi_sdDat0Idle;
                    spi_resp[`Resp_Arg_SDStatus_Resp_Bits] <= sd_resp_data;
                end
                
                `Msg_Type_SDReadout: begin
                    $display("[SPI] Got Msg_Type_SDReadout");
                    spi_sdReadoutCounter <= 6;
                    spi_state <= SPI_State_SDReadout;
                end
                
                `Msg_Type_ImgReset: begin
                    $display("[SPI] Got Msg_Type_ImgReset (rst=%b)", spi_msgArg[`Msg_Arg_ImgReset_Val_Bits]);
                    img_rst_ <= spi_msgArg[`Msg_Arg_ImgReset_Val_Bits];
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
                spi_doutCounter <= 1;
                spi_sdReadoutEnding <= 0;
                if (!spi_sdReadoutCounter) begin
                    spi_sdReadoutCounter <= SDReadoutCount;
                    spi_state <= SPI_State_SDReadout+1;
                end
            end
            
            SPI_State_SDReadout+1: begin
                spi_d_outEn <= 1;
                
                // if (fifo_r_trigger) begin
                //     $display("AAA Read word: %x", fifo_r_data);
                // end
                
                if (!spi_doutCounter) begin
                    spi_doutReg <= fifo_r_data;
                    fifo_r_trigger <= !spi_sdReadoutEnding;
                end
                
                if (!spi_sdReadoutCounter) begin
                    spi_sdReadoutCounter <= 3;
                    spi_state <= SPI_State_SDReadout;
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
