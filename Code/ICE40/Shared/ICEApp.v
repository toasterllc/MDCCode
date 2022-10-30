`ifndef ICEApp_v
`define ICEApp_v

// TODO: have consistent ordering for FIFO ports for: AFIFO, AFIFOChain, SDController, ImgController
//       clk, trigger, data, ready

// TODO: try to make width of SDController data nets a parameter (4, 8, 16, ...), so that ICEAppSTM can use width=8 to read, but ICEAppMSP can use width=16 to write

`include "ICEAppTypes.v"
`include "Util.v"
`include "Sync.v"
`include "ToggleAck.v"
`include "ClockGen.v"
`include "SDController.v"
`include "ImgController.v"
`include "ImgI2CMaster.v"
`include "AFIFOChain.v"

`timescale 1ns/1ps

`ifdef ICEApp_ImgReadoutToSD_En
    `define _ICEApp_Img_En
    `define _ICEApp_SD_En
`endif

`ifdef ICEApp_SDReadoutToSPI_En
    `define _ICEApp_SD_En
    `define _ICEApp_SPIReadout_En
`endif

`ifdef ICEApp_ImgReadoutToSPI_En
    `define _ICEApp_Img_En
    `define _ICEApp_SPIReadout_En
`endif

module ICEApp(
    input wire          ice_img_clk16mhz,
    
`ifdef ICEApp_MSP_En
    // MSP SPI port
    input wire          ice_msp_spi_clk,
    inout wire          ice_msp_spi_data,
`endif // ICEApp_MSP_En
    
`ifdef ICEApp_STM_En
    // STM SPI port
    input wire          ice_stm_spi_clk,
    input wire          ice_stm_spi_cs_,
    inout wire[7:0]     ice_stm_spi_d,
    output wire         ice_stm_spi_d_ready,
`endif // ICEApp_STM_En
    
`ifdef _ICEApp_SD_En
    // SD port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
`endif // _ICEApp_SD_En
    
`ifdef _ICEApp_Img_En
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
`endif // _ICEApp_Img_En
    
    // LED port
    output reg[3:0]     ice_led = 0
    
`ifdef SIM
    // Exported so that the sim can verify that the state machine is in reset
    , output wire         sim_spiRst_
`endif // SIM
);
    // ====================
    // spi_clk
    // ====================
    wire spi_clk;
    
    
    
    
    
    
`ifdef _ICEApp_Img_En
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
`else // !SIM
        .I2CClkFreq(100_000) // TODO: try 400_000 (the max frequency) to see if it works. if not, the pullup's likely too weak.
`endif // SIM
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
    // ImgController
    // ====================
    reg                                     imgctrl_cmd_capture = 0;
    reg                                     imgctrl_cmd_readout = 0;
    reg[0:0]                                imgctrl_cmd_ramBlock = 0;
    reg[0:0]                                imgctrl_cmd_skipCount = 0;
    reg[`Img_HeaderWordCount*16-1:0]        imgctrl_cmd_header = 0;
    reg                                     imgctrl_cmd_thumb = 0;
    wire                                    imgctrl_readout_rst;
    wire                                    imgctrl_readout_start;
    wire                                    imgctrl_readout_ready;
    wire                                    imgctrl_readout_trigger;
    wire[15:0]                              imgctrl_readout_data;
    wire                                    imgctrl_readout_done;
    wire                                    imgctrl_status_captureDone;
    wire[`RegWidth(`Img_WordCount)-1:0]     imgctrl_status_capturePixelCount;
    wire[17:0]                              imgctrl_status_captureHighlightCount;
    wire[17:0]                              imgctrl_status_captureShadowCount;
    // ImgCtrl_PaddingWordCount: padding so that ImgController readout outputs enough
    // data to trigger the AFIFOChain read threshold (`readoutfifo_r_thresh`)
    localparam ImgCtrl_AFIFOWordCapacity = (`AFIFO_CapacityBytes/2);
    localparam ImgCtrl_ReadoutWordThresh = ReadoutFIFO_R_Thresh*ImgCtrl_AFIFOWordCapacity;
    localparam ImgCtrl_PaddingWordCount = ImgCtrl_ReadoutWordThresh-1;
    ImgController #(
        .ClkFreq(Img_Clk_Freq),
        .HeaderWordCount(`Img_HeaderWordCount),
        .ImgWidth(`Img_Width),
        .ImgHeight(`Img_Height),
        .PaddingWordCount(ImgCtrl_PaddingWordCount)
    ) ImgController (
        .clk(img_clk),
        
        .cmd_capture(imgctrl_cmd_capture),
        .cmd_readout(imgctrl_cmd_readout),
        .cmd_ramBlock(imgctrl_cmd_ramBlock),
        .cmd_skipCount(imgctrl_cmd_skipCount),
        .cmd_header(imgctrl_cmd_header),
        .cmd_thumb(imgctrl_cmd_thumb),
        
        .readout_rst(imgctrl_readout_rst),
        .readout_start(imgctrl_readout_start),
        .readout_ready(imgctrl_readout_ready),
        .readout_trigger(imgctrl_readout_trigger),
        .readout_data(imgctrl_readout_data),
        .readout_done(imgctrl_readout_done),
        
        .status_captureDone(imgctrl_status_captureDone),
        .status_capturePixelCount(imgctrl_status_capturePixelCount),
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
`endif // _ICEApp_Img_En
    
    
    
    
    
    
    // ====================
    // AFIFOChain
    // ====================
    // ReadoutFIFO_FIFOCount: 4096*8=32768 bits=4096 bytes total
    localparam ReadoutFIFO_FIFOCount = 8;
    // ReadoutFIFO_W_Thresh: Signal `readoutfifo_w_thresh` when >=1 FIFO is empty
    localparam ReadoutFIFO_W_Thresh = 1;
    
`ifdef _ICEApp_SPIReadout_En
    // ReadoutFIFO_R_Thresh: Signal `readoutfifo_r_thresh` when >=4 FIFOs are full (SPI master
    // consumes 2048-byte chunks)
    localparam ReadoutFIFO_R_Thresh = 4;
`else
    // ReadoutFIFO_R_Thresh: Signal `readoutfifo_r_thresh` when >=1 FIFO is full (SDController
    // consumes 512-byte chunks)
    localparam ReadoutFIFO_R_Thresh = 1;
`endif
    
    wire        readoutfifo_rst_;
    wire        readoutfifo_prop_clk;
    wire        readoutfifo_w_clk;
    wire        readoutfifo_w_trigger;
    wire[15:0]  readoutfifo_w_data;
    wire        readoutfifo_w_ready;
    wire        readoutfifo_w_thresh;
    wire        readoutfifo_r_clk;
    wire        readoutfifo_r_trigger;
    wire[15:0]  readoutfifo_r_data;
    wire        readoutfifo_r_ready;
    wire        readoutfifo_r_thresh;
    wire        readoutfifo_async_w_thresh;
    wire        readoutfifo_async_r_thresh;
    
    AFIFOChain #(
        .W(16),
        .N(ReadoutFIFO_FIFOCount),
        .W_Thresh(ReadoutFIFO_W_Thresh),
        .R_Thresh(ReadoutFIFO_R_Thresh)
    ) AFIFOChain(
        .rst_(readoutfifo_rst_),
        
        .prop_clk(readoutfifo_prop_clk),
        
        .w_clk(readoutfifo_w_clk),
        .w_trigger(readoutfifo_w_trigger),
        .w_data(readoutfifo_w_data),
        .w_ready(readoutfifo_w_ready),
        .w_thresh(readoutfifo_w_thresh),
        
        .r_clk(readoutfifo_r_clk),
        .r_trigger(readoutfifo_r_trigger),
        .r_data(readoutfifo_r_data),
        .r_ready(readoutfifo_r_ready),
        .r_thresh(readoutfifo_r_thresh),
        
        .async_w_thresh(readoutfifo_async_w_thresh),
        .async_r_thresh(readoutfifo_async_r_thresh)
    );
    
    assign readoutfifo_prop_clk    = readoutfifo_w_clk;
    
`ifdef _ICEApp_SD_En
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
    
    // Config port (clock domain: async)
    reg sd_config_trigger = 0;
    reg[`SDController_Config_Action_Width-1:0]
                sd_config_action = 0;
    reg[`SDController_Config_ClkSpeed_Width-1:0]
                sd_config_clkSpeed = 0;
    reg[`SDController_Config_ClkDelay_Width-1:0]
                sd_config_clkDelay = 0;
    reg[`SDController_Config_PinMode_Width-1:0]
                sd_config_pinMode = 0;
    reg         sd_cmd_trigger          = 0;
    reg[47:0]   sd_cmd_data             = 0;
    reg[1:0]    sd_cmd_respType         = 0;
    reg[1:0]    sd_cmd_datInType        = 0;
    wire        sd_cmd_done;
    wire        sd_resp_done;
    wire[135:0] sd_resp_data;
    wire        sd_resp_crcErr;
    wire        sd_datOut_trigger;
    wire        sd_datOut_ready;
    wire        sd_datOut_done;
    wire        sd_datOut_crcErr;
    wire        sd_datOutRead_clk;
    wire        sd_datOutRead_ready;
    wire        sd_datOutRead_trigger;
    wire[15:0]  sd_datOutRead_data;
    wire        sd_datOutRead_done;
    wire        sd_datIn_done;
    wire        sd_datIn_crcErr;
    wire        sd_datInWrite_rst;
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
        
        .config_trigger(sd_config_trigger),
        .config_action(sd_config_action),
        .config_clkSpeed(sd_config_clkSpeed),
        .config_clkDelay(sd_config_clkDelay),
        .config_pinMode(sd_config_pinMode),
        
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
        .datOutRead_done(sd_datOutRead_done),
        
        .datIn_done(sd_datIn_done),
        .datIn_crcErr(sd_datIn_crcErr),
        
        .datInWrite_rst(sd_datInWrite_rst),
        .datInWrite_clk(sd_datInWrite_clk),
        .datInWrite_ready(sd_datInWrite_ready),
        .datInWrite_trigger(sd_datInWrite_trigger),
        .datInWrite_data(sd_datInWrite_data),
        
        .status_dat0Idle(sd_status_dat0Idle)
    );
    
    // ====================
    // CMD6 Access Mode Capture
    // ====================
    reg[3:0] sd_cmd6_accessMode = 0;
    reg[`RegWidth((512/16)-1)-1:0] sd_cmd6_counter = 0;
    wire sd_cmd6_datInWrite = sd_datInWrite_trigger && sd_datInWrite_ready;
    
    // If SDReadoutToSPI is enabled, then the AFIFO chain needs to control `sd_datInWrite_ready`.
    // Otherwise (ie when ICEApp_SDReadoutToSPI_En==0), set sd_datInWrite_ready=1 so that DatIn
    // data is always accepted.
`ifndef ICEApp_SDReadoutToSPI_En
    assign sd_datInWrite_ready = 1;
`endif // ICEApp_SDReadoutToSPI_En
    
    always @(posedge sd_datInWrite_clk) begin
        if (sd_datInWrite_rst) begin
            sd_cmd6_counter <= '1;
        
        end else if (sd_cmd6_datInWrite) begin
            sd_cmd6_counter <= sd_cmd6_counter-1;
            
            if (sd_cmd6_counter === 23) begin
                sd_cmd6_accessMode <= sd_datInWrite_data[11:8];
                // $display("[SPI] sd_cmd6_accessMode: %h", sd_datInWrite_data[11:8]);
            end
        end
    end
`endif // _ICEApp_SD_En
    
`ifdef ICEApp_ImgReadoutToSD_En
    assign readoutfifo_rst_         = !imgctrl_readout_rst;
    assign readoutfifo_w_clk        = img_clk;
    assign readoutfifo_w_trigger    = imgctrl_readout_ready;
    assign readoutfifo_w_data       = imgctrl_readout_data;
    assign readoutfifo_r_clk        = sd_datOutRead_clk;
    assign readoutfifo_r_trigger    = sd_datOutRead_trigger;
    assign sd_datOut_trigger        = imgctrl_readout_start;
    assign sd_datOutRead_ready      = readoutfifo_r_thresh;
    assign sd_datOutRead_data       = readoutfifo_r_data;
    assign imgctrl_readout_trigger  = readoutfifo_w_ready;
    
    `Sync(sd_datOutRead_doneX, imgctrl_readout_done, posedge, sd_datOutRead_clk);
    assign sd_datOutRead_done = sd_datOutRead_doneX;
`endif // ICEApp_ImgReadoutToSD_En
    
`ifdef ICEApp_SDReadoutToSPI_En
    assign readoutfifo_rst_         = !sd_datInWrite_rst;
    assign readoutfifo_w_clk        = sd_datInWrite_clk;
    assign readoutfifo_w_trigger    = sd_datInWrite_trigger;
    assign readoutfifo_w_data       = sd_datInWrite_data;
    assign readoutfifo_r_clk        = spi_clk;
    assign readoutfifo_r_trigger    = spi_readoutTrigger;
    assign sd_datOut_trigger        = 0;
    assign sd_datInWrite_ready      = readoutfifo_w_thresh;
`endif // ICEApp_SDReadoutToSPI_En
    
`ifdef ICEApp_ImgReadoutToSPI_En
    assign readoutfifo_rst_         = !imgctrl_readout_rst;
    assign readoutfifo_w_clk        = img_clk;
    assign readoutfifo_w_trigger    = imgctrl_readout_ready;
    assign readoutfifo_w_data       = imgctrl_readout_data;
    assign readoutfifo_r_clk        = spi_clk;
    assign readoutfifo_r_trigger    = spi_readoutTrigger;
    assign imgctrl_readout_trigger  = readoutfifo_w_ready;
`endif // ICEApp_ImgReadoutToSPI_En
    
`ifdef ICEApp_MSP_En
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
    assign spi_rst_ = !(&spirst_counter);
    always @(posedge spirst_clk) begin
        spirst_counter <= spirst_counter;
        if (!spirst_spiClkSynced) begin
            spirst_counter <= 0;
        end else if (spi_rst_) begin
            spirst_counter <= spirst_counter+1;
        end
    end
`endif // ICEApp_MSP_En
    
`ifdef SIM
    assign sim_spiRst_ = spi_rst_;
`endif // SIM
    
    // ====================
    // SPI State Machine
    // ====================
    
`ifdef _ICEApp_SD_En
    // SD nets
    `ToggleAck(spi_sdCmdDone_, spi_sdCmdDoneAck, sd_cmd_done, posedge, spi_clk);
    `ToggleAck(spi_sdRespDone_, spi_sdRespDoneAck, sd_resp_done, posedge, spi_clk);
    `Sync(spi_sdDatOutDone, sd_datOut_done, posedge, spi_clk);
    `ToggleAck(spi_sdDatInDone_, spi_sdDatInDoneAck, sd_datIn_done, posedge, spi_clk);
    `Sync(spi_sdDat0Idle, sd_status_dat0Idle, posedge, spi_clk);
`endif // _ICEApp_SD_En
    
`ifdef _ICEApp_Img_En
    // IMG nets
    `ToggleAck(spi_imgCaptureDone_, spi_imgCaptureDoneAck, imgctrl_status_captureDone, posedge, spi_clk);
`endif // _ICEApp_Img_En
    
`ifdef ICEApp_MSP_En
    // SPI control nets
    localparam TurnaroundDelay = 8;
    localparam TurnaroundInherentDelay = 2; // TODO: =4 when `SB_IO_ice_msp_spi_data` registers the input
    localparam TurnaroundExtraDelay = TurnaroundDelay-TurnaroundInherentDelay;
    localparam MsgCycleCount = `Msg_Len+TurnaroundExtraDelay-2;
    localparam RespCycleCount = `Resp_Len;
    
    localparam SPI_State_MsgIn      = 0;    // +2
    localparam SPI_State_RespOut    = 3;    // +0
    localparam SPI_State_Count      = 4;
    
    reg[`RegWidth2(MsgCycleCount,RespCycleCount)-1:0] spi_dataCounter = 0;
    reg[TurnaroundExtraDelay-1:0] spi_dataInDelayed = 0;
    reg spi_dataOut = 0;
    wire spi_dataIn;
    wire spi_dataInRaw = ice_msp_spi_data;
    
    assign spi_msgType = spi_msg[`Msg_Type_Bits];
`endif // ICEApp_MSP_En
    
`ifdef ICEApp_STM_En
    // SPI control nets
    
    // MsgCycleCount notes:
    //
    //   - We include a dummy byte at the beginning of each command, to workaround an
    //     apparent STM32 bug that always sends the first nibble as 0xF. As such, we
    //     need to add 2 cycles to `MsgCycleCount`. Without this dummy byte,
    //     MsgCycleCount=(`Msg_Len/4)-1, so with this dummy byte,
    //     MsgCycleCount=(`Msg_Len/4)+1.
    //
    //   - Commands use 4 lines (ice_stm_ice_stm_spi_d[3:0]), so we divide `Msg_Len by 4.
    //     Commands use only 4 lines, instead of all 8 lines used for responses,
    //     because dual-QSPI doesn't allow that, since dual-QSPI is meant to control
    //     two separate flash devices, so it outputs the same data on ice_stm_ice_stm_spi_d[3:0]
    //     that it does on ice_stm_ice_stm_spi_d[7:4].
    localparam MsgCycleCount = (`Msg_Len/4)+1;
    
    localparam SPI_State_MsgIn      = 0;    // +2
    localparam SPI_State_RespOut    = 3;    // +0
    localparam SPI_State_Readout    = 4;    // +1
    localparam SPI_State_Nop        = 6;    // +0
    localparam SPI_State_Count      = 7;
    
    reg[`RegWidth(MsgCycleCount)-1:0] spi_dataCounter = 0;
    reg spi_dataOutLoad_ = 0;
    reg[15:0] spi_dataOut = 0;
    wire[7:0] spi_dataIn;
    wire[7:0] spi_dataInRaw = ice_stm_spi_d;
    
    // spi_msgTypeRaw / spi_msgType: STM32's QSPI messaging mechanism doesn't allow
    // for setting the first bit to 1, so we fake the first bit.
    wire[`Msg_Type_Len-1:0] spi_msgTypeRaw = spi_msg[`Msg_Type_Bits];
    assign spi_msgType = {1'b1, spi_msgTypeRaw[`Msg_Type_Len-2:0]};
`endif // ICEApp_STM_En
    
`ifdef _ICEApp_SPIReadout_En
    localparam SPI_ReadoutBitCount      = ((ReadoutFIFO_FIFOCount/2)*4096)/8;
    localparam SPI_ReadoutCycleCount    = SPI_ReadoutBitCount+3;
    reg[`RegWidth(SPI_ReadoutCycleCount)-1:0] spi_readoutCounter = 0;
    reg spi_readoutTrigger = 0;
    reg spi_readoutEnding = 0;
`endif // _ICEApp_SPIReadout_En
    
    reg[`RegWidth(SPI_State_Count-1)-1:0] spi_state = 0;
    reg[`Msg_Len-1:0] spi_msg = 0;
    reg spi_dataOutEn = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    
    wire[`Msg_Type_Len-1:0] spi_msgType;
    wire spi_msgResp = spi_msgType[`Msg_Type_Resp_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_msg[`Msg_Arg_Bits];
    wire spi_rst_;
    
    always @(posedge spi_clk, negedge spi_rst_) begin
        if (!spi_rst_) begin
            $display("[SPI] Reset");
            
            spi_state <= SPI_State_MsgIn;
            spi_dataOutEn <= 0;
            
            `ifdef _ICEApp_SPIReadout_En
                spi_readoutTrigger <= 0;
            `endif // _ICEApp_SPIReadout_En
        
        end else begin
        
            spi_dataOutEn <= 0;
            spi_dataCounter <= spi_dataCounter-1;
            
            `ifdef ICEApp_MSP_En
                spi_msg <= spi_msg<<1|`LeftBit(spi_dataInDelayed,0);
                spi_dataInDelayed <= spi_dataInDelayed<<1|spi_dataIn;
                spi_resp <= spi_resp<<1|1'b0;
                spi_dataOut <= `LeftBit(spi_resp, 0);
            `endif // ICEApp_MSP_En
            
            `ifdef ICEApp_STM_En
                // Commands only use 4 lines (ice_stm_spi_d[3:0]) because it's quadspi.
                // See MsgCycleCount comment above.
                spi_msg <= spi_msg<<4|spi_dataIn[3:0];
                spi_dataOutLoad_ <= !spi_dataOutLoad_;
                spi_resp <= spi_resp<<8|8'b0;
                spi_dataOut <= spi_dataOut<<4;
            `endif // ICEApp_STM_En
            
            `ifdef _ICEApp_SPIReadout_En
                spi_readoutTrigger <= 0;
                spi_readoutCounter <= spi_readoutCounter-1;
                if (spi_readoutCounter === 4) spi_readoutEnding <= 1;
            `endif // _ICEApp_SPIReadout_En
            
            case (spi_state)
            SPI_State_MsgIn: begin
                // Verify that we never get a clock while spi_dataInRaw is undriven (z) / invalid (x)
                if (!`ValidBits(spi_dataInRaw)) begin
                    $display("spi_dataInRaw invalid: %b (time: %0d, spi_rst_: %b) ❌", spi_dataInRaw, $time, spi_rst_);
                    #1000;
                    `Finish;
                end
                
                `ifdef ICEApp_MSP_En
                    // Wait for the start of the message, signified by the first high bit
                    if (spi_dataIn) begin
                        spi_dataCounter <= MsgCycleCount;
                        spi_state <= SPI_State_MsgIn+1;
                    end
                `endif // ICEApp_MSP_En
                
                `ifdef ICEApp_STM_En
                    spi_dataCounter <= MsgCycleCount;
                    spi_state <= SPI_State_MsgIn+1;
                `endif // ICEApp_STM_En
            end
            
            SPI_State_MsgIn+1: begin
                if (!spi_dataCounter) begin
                    spi_state <= SPI_State_MsgIn+2;
                end
            end
            
            SPI_State_MsgIn+2: begin
                spi_state <= SPI_State_RespOut;
                
                `ifdef ICEApp_MSP_En
                    spi_dataCounter <= (spi_msgResp ? RespCycleCount : 0);
                `endif // ICEApp_MSP_En
                
                `ifdef ICEApp_STM_En
                    spi_dataOutLoad_ <= 0;
                `endif // ICEApp_STM_En
                
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
                
`ifdef _ICEApp_SD_En
                // Set SD clock source
                `Msg_Type_SDConfig: begin
                    $display("[SPI] Got Msg_Type_SDConfig: action=%0d speed=%0d delay=%0d pinMode=%0d",
                        spi_msgArg[`Msg_Arg_SDConfig_Action_Bits],
                        spi_msgArg[`Msg_Arg_SDConfig_ClkSpeed_Bits],
                        spi_msgArg[`Msg_Arg_SDConfig_ClkDelay_Bits],
                        spi_msgArg[`Msg_Arg_SDConfig_PinMode_Bits]
                    );
                    
                    sd_config_trigger   <= !sd_config_trigger;
                    sd_config_action    <= spi_msgArg[`Msg_Arg_SDConfig_Action_Bits];
                    sd_config_clkSpeed  <= spi_msgArg[`Msg_Arg_SDConfig_ClkSpeed_Bits];
                    sd_config_clkDelay  <= spi_msgArg[`Msg_Arg_SDConfig_ClkDelay_Bits];
                    sd_config_pinMode   <= spi_msgArg[`Msg_Arg_SDConfig_PinMode_Bits];
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
                        spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits] <= sd_cmd6_accessMode;
                    spi_resp[`Resp_Arg_SDStatus_Dat0Idle_Bits] <= spi_sdDat0Idle;
                    spi_resp[`Resp_Arg_SDStatus_Resp_Bits] <= sd_resp_data;
                end
                
                // Get SD status / response
                `Msg_Type_SDResp: begin
                    $display("[SPI] Got Msg_Type_SDResp");
                    case (spi_msgArg[`Msg_Arg_SDResp_Idx_Bits])
                    0: spi_resp[`Resp_Arg_SDResp_Resp_Bits] <= sd_resp_data[127:64];
                    1: spi_resp[`Resp_Arg_SDResp_Resp_Bits] <= sd_resp_data[63:0];
                    endcase
                end
`endif // _ICEApp_SD_En
                
`ifdef _ICEApp_Img_En
                `Msg_Type_ImgReset: begin
                    $display("[SPI] Got Msg_Type_ImgReset (rst=%b)", spi_msgArg[`Msg_Arg_ImgReset_Val_Bits]);
                    img_rst_ <= spi_msgArg[`Msg_Arg_ImgReset_Val_Bits];
                end
                
                `Msg_Type_ImgSetHeader: begin
                    $display("[SPI] Got Msg_Type_ImgSetHeader (idx=%h, header=%h)",
                        spi_msgArg[`Msg_Arg_ImgSetHeader_Idx_Bits],
                        spi_msgArg[`Msg_Arg_ImgSetHeader_Header_Bits]
                    );
                    
                    case (spi_msgArg[`Msg_Arg_ImgSetHeader_Idx_Bits])
                    0: `LeftBits(imgctrl_cmd_header,0*48,48) <= spi_msgArg[`Msg_Arg_ImgSetHeader_Header_Bits];
                    1: `LeftBits(imgctrl_cmd_header,1*48,48) <= spi_msgArg[`Msg_Arg_ImgSetHeader_Header_Bits];
                    2: `LeftBits(imgctrl_cmd_header,2*48,48) <= spi_msgArg[`Msg_Arg_ImgSetHeader_Header_Bits];
                    3: `LeftBits(imgctrl_cmd_header,3*48,48) <= spi_msgArg[`Msg_Arg_ImgSetHeader_Header_Bits];
                    endcase
                end
                
                `Msg_Type_ImgCapture: begin
                    $display("[SPI] Got Msg_Type_ImgCapture (skipCount=%d, block=%d)",
                        spi_msgArg[`Msg_Arg_ImgCapture_SkipCount_Bits],
                        spi_msgArg[`Msg_Arg_ImgCapture_DstRAMBlock_Bits]);
                    // Reset spi_imgCaptureDone_
                    if (!spi_imgCaptureDone_) spi_imgCaptureDoneAck <= !spi_imgCaptureDoneAck;
                    imgctrl_cmd_ramBlock <= spi_msgArg[`Msg_Arg_ImgCapture_DstRAMBlock_Bits];
                    imgctrl_cmd_skipCount <= spi_msgArg[`Msg_Arg_ImgCapture_SkipCount_Bits];
                    imgctrl_cmd_capture <= !imgctrl_cmd_capture;
                end
                
                `Msg_Type_ImgCaptureStatus: begin
                    $display("[SPI] Got Msg_Type_ImgCaptureStatus");
                    spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits] <= !spi_imgCaptureDone_;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_PixelCount_Bits] <= imgctrl_status_capturePixelCount;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits] <= imgctrl_status_captureHighlightCount;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits] <= imgctrl_status_captureShadowCount;
                end
                
                `Msg_Type_ImgReadout: begin
                    $display("[SPI] Got Msg_Type_ImgReadout");
                    imgctrl_cmd_ramBlock <= spi_msgArg[`Msg_Arg_ImgReadout_SrcRAMBlock_Bits];
                    imgctrl_cmd_thumb <= spi_msgArg[`Msg_Arg_ImgReadout_Thumb_Bits];
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
                    $display("[SPI] Got Msg_Type_ImgI2CStatus done_:%0d err:%0d readData:0x%h)",
                        spi_imgi2c_done_,
                        imgi2c_status_err,
                        imgi2c_status_readData
                    );
                    spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits] <= !spi_imgi2c_done_;
                    spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits] <= imgi2c_status_err;
                    spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits] <= imgi2c_status_readData;
                end
`endif // _ICEApp_Img_En
                
`ifdef _ICEApp_SPIReadout_En
                `Msg_Type_Readout: begin
                    $display("[SPI] Got Msg_Type_Readout");
                    spi_readoutCounter <= 6;
                    spi_state <= SPI_State_Readout;
                end
`endif // _ICEApp_SPIReadout_En
                
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
                `ifdef ICEApp_MSP_En
                    if (spi_dataCounter) begin
                        spi_dataOutEn <= 1;
                    end else begin
                        spi_state <= SPI_State_MsgIn;
                    end
                `endif // ICEApp_MSP_En
                
                `ifdef ICEApp_STM_En
                    spi_dataOutEn <= 1;
                    if (!spi_dataOutLoad_) begin
                        spi_dataOut <= `LeftBits(spi_resp, 0, 16);
                    end
                `endif // ICEApp_STM_En
            end
            
`ifdef _ICEApp_SPIReadout_En
            SPI_State_Readout: begin
                spi_dataOutLoad_ <= 1;
                spi_readoutEnding <= 0;
                if (!spi_readoutCounter) begin
                    spi_readoutCounter <= SPI_ReadoutCycleCount;
                    spi_state <= SPI_State_Readout+1;
                end
            end
            
            SPI_State_Readout+1: begin
                spi_dataOutEn <= 1;
                
                if (!spi_dataOutLoad_) begin
                    spi_dataOut <= readoutfifo_r_data;
                    spi_readoutTrigger <= !spi_readoutEnding;
                end
                
                if (!spi_readoutCounter) begin
                    spi_readoutCounter <= 3;
                    spi_state <= SPI_State_Readout;
                end
            end
`endif // _ICEApp_SPIReadout_En
            
            endcase
        end
    end
    
    
    
`ifdef ICEApp_MSP_En
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
`endif // ICEApp_MSP_En
    
`ifdef ICEApp_STM_En
    // ====================
    // Pin: ice_stm_spi_clk
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b0000_01) // Output: none; input: unregistered
    ) SB_IO_ice_stm_spi_clk (
        .PACKAGE_PIN(ice_stm_spi_clk),
        .D_IN_0(spi_clk)
    );
    
    // ====================
    // Pin: ice_stm_spi_cs_
    // ====================
    wire spi_cs_;
    SB_IO #(
        .PIN_TYPE(6'b0000_01), // Output: none; input: unregistered
        .PULLUP(1'b1)
    ) SB_IO_ice_stm_spi_cs_ (
        .PACKAGE_PIN(ice_stm_spi_cs_),
        .D_IN_0(spi_cs_)
    );
    assign spi_rst_ = !spi_cs_;
    
    // ====================
    // Pin: ice_stm_spi_d
    // ====================
    wire[7:0] spi_dataOutQSPIMangled = {
        `LeftBits(spi_dataOut, 8, 4),   // High 4 bits: 4 bits of byte 1
        `LeftBits(spi_dataOut, 0, 4)    // Low 4 bits:  4 bits of byte 0
    };
    
    genvar i;
    for (i=0; i<8; i++) begin
        SB_IO #(
            .PIN_TYPE(6'b1001_00) // Output: registered with unregistered enable; input: registered
        ) SB_IO_ice_stm_spi_d (
            .INPUT_CLK(spi_clk),
            .OUTPUT_CLK(spi_clk),
            .PACKAGE_PIN(ice_stm_spi_d[i]),
            .OUTPUT_ENABLE(spi_dataOutEn),
            .D_OUT_0(spi_dataOutQSPIMangled[i]),
            .D_IN_0(spi_dataIn[i])
        );
    end
    
    // ====================
    // Pin: ice_stm_spi_d_ready
    // ====================
    // ice_stm_spi_d_ready: we have to use AFIFOChain's `async_r_thresh` (the r_clk async version),
    // not `r_thresh` (the r_clk sync version) because when STM32 is waiting for data, it's not
    // driving spi_clk (AFIFOChain's r_clk), so `r_thresh` is never asserted. `async_r_thresh`
    // is driven by AFIFOChain's `w_clk`, so it can toggle while `r_clk` is halted.
    assign ice_stm_spi_d_ready = readoutfifo_async_r_thresh;
`endif // ICEApp_STM_En
    
endmodule

`endif // ICEApp_v
