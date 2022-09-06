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
`include "ImgController.v"
`include "ImgI2CMaster.v"
`include "RAMController.v"
`include "ICEAppTypes.v"

`ifdef SIM
`include "ImgSim.v"
`include "ImgI2CSlaveSim.v"
`include "mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    input wire          ice_st_spi_clk,
    input wire          ice_st_spi_cs_,
    inout wire[7:0]     ice_st_spi_d,
    
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
    inout wire[15:0]    ram_dq
    
    // output reg[3:0]     ice_led = 0
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
    `ToggleAck(spi_imgi2c_done_, spi_imgi2c_doneAck, imgi2c_status_done, posedge, ice_st_spi_clk);
    
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
    reg[1:0]                            imgctrl_cmd = 0;
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
    wire                                imgctrl_status_readoutStarted;
    ImgController #(
        .ClkFreq(Img_Clk_Freq),
        .ImageWidthMax(ImageWidthMax),
        .ImageHeightMax(ImageHeightMax)
    ) ImgController (
        .clk(img_clk),
        
        .cmd(imgctrl_cmd),
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
        .status_readoutStarted(imgctrl_status_readoutStarted),
        
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
    
    reg spi_imgCaptureTrigger = 0;
    `TogglePulse(img_captureTrigger, spi_imgCaptureTrigger, posedge, img_clk);
    reg img_readoutStarted = 0;
    
    localparam Img_State_Idle       = 0;    // +0
    localparam Img_State_Capture    = 1;    // +1
    localparam Img_State_Readout    = 3;    // +0
    localparam Img_State_Count      = 4;
    reg[`RegWidth(Img_State_Count-1)-1:0] img_state = 0;
    always @(posedge img_clk) begin
        imgctrl_cmd <= `ImgController_Cmd_None;
        
        case (img_state)
        Img_State_Idle: begin
        end
        
        Img_State_Capture: begin
            // Start a capture
            imgctrl_cmd <= `ImgController_Cmd_Capture;
            img_state <= Img_State_Capture+1;
        end
        
        Img_State_Capture+1: begin
            // Wait for the capture to complete, and then start readout
            if (imgctrl_status_captureDone) begin
                imgctrl_cmd <= `ImgController_Cmd_Readout;
                img_state <= Img_State_Readout;
            end
        end
        
        Img_State_Readout: begin
            // Wait for readout to start, and then signal so via img_readoutStarted
            if (imgctrl_status_readoutStarted) begin
                img_readoutStarted <= !img_readoutStarted;
                img_state <= Img_State_Idle;
            end
        end
        endcase
        
        if (img_captureTrigger) begin
            // ice_led <= 4'b1111;
            img_state <= Img_State_Capture;
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
    wire[`Msg_Type_Len-1:0] spi_msgType = spi_dinReg[`Msg_Type_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_dinReg[`Msg_Arg_Bits];
    reg[`Msg_Arg_ImgReadout_Counter_Len-1:0] spi_imgReadoutCounter = 0;
    reg spi_imgReadoutDone = 0;
    reg spi_imgReadoutCaptureNext = 0;
    
    wire spi_cs;
    reg spi_d_outEn = 0;
    wire[7:0] spi_d_out;
    wire[7:0] spi_d_in;
    
    assign spi_d_out = {
        `LeftBits(spi_doutReg, 8, 4),   // High 4 bits: 4 bits of byte 1
        `LeftBits(spi_doutReg, 0, 4)    // Low 4 bits:  4 bits of byte 0
    };
    
    `ToggleAck(spi_imgReadoutStarted, spi_imgReadoutStartedAck, img_readoutStarted, posedge, ice_st_spi_clk);
    
    assign imgctrl_readout_clk = ice_st_spi_clk;
    wire spi_imgctrlReadoutReady = imgctrl_readout_ready;
    reg spi_imgctrlReadoutTrigger = 0;
    assign imgctrl_readout_trigger = spi_imgctrlReadoutTrigger;
    wire[15:0] spi_imgctrlReadoutData = imgctrl_readout_data;
    // `spi_imgReadoutReady` combines the state of (1) readout having started, and (2) data being available in the FIFO.
    // This is so that a new ImgCapture message that interrupts a readout will force `spi_imgReadoutReady`=0,
    // because `spi_imgReadoutStarted`=0 until the new capture is complete and readout starts.
    wire spi_imgReadoutReady = spi_imgReadoutStarted && spi_imgctrlReadoutReady;
    
    localparam SPI_State_MsgIn      = 0;    // +2
    localparam SPI_State_RespOut    = 3;    // +0
    localparam SPI_State_ImgOut     = 4;    // +0
    localparam SPI_State_Nop        = 5;    // +0
    localparam SPI_State_Count      = 6;
    reg[`RegWidth(SPI_State_Count-1)-1:0] spi_state = 0;
    
    always @(posedge ice_st_spi_clk, negedge spi_cs) begin
        // Reset ourself when we're de-selected
        if (!spi_cs) begin
            spi_state <= 0;
            spi_d_outEn <= 0;
        
        end else begin
            // Commands only use 4 lines (ice_st_spi_d[3:0]) because it's quadspi.
            // See MsgCycleCount comment above.
            spi_dinReg <= spi_dinReg<<4|spi_d_in[3:0];
            spi_dinCounter <= spi_dinCounter-1;
            spi_doutReg <= spi_doutReg<<4|4'hF;
            spi_doutCounter <= spi_doutCounter-1;
            spi_d_outEn <= 0;
            spi_resp <= spi_resp<<8|8'hFF;
            
            spi_imgReadoutCounter <= spi_imgReadoutCounter-1;
            if (!spi_imgReadoutCounter) spi_imgReadoutDone <= 1;
            spi_imgctrlReadoutTrigger <= 0;
            
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
                
                `Msg_Type_ImgReset: begin
                    $display("[SPI] Got Msg_Type_ImgReset (rst=%b)", spi_msgArg[`Msg_Arg_ImgReset_Val_Bits]);
                    img_rst_ <= spi_msgArg[`Msg_Arg_ImgReset_Val_Bits];
                end
                
                `Msg_Type_ImgCapture: begin
                    $display("[SPI] Got Msg_Type_ImgCapture (block=%b)", spi_msgArg[`Msg_Arg_ImgCapture_DstRAMBlock_Bits]);
                    imgctrl_cmd_ramBlock <= spi_msgArg[`Msg_Arg_ImgCapture_DstRAMBlock_Bits];
                    spi_imgCaptureTrigger <= !spi_imgCaptureTrigger;
                end
                
                `Msg_Type_ImgReadout: begin
                    $display("[SPI] Got Msg_Type_ImgReadout");
                    // Reset `spi_imgReadoutStarted` if it's asserted
                    if (spi_imgReadoutStarted) spi_imgReadoutStartedAck <= !spi_imgReadoutStartedAck;
                    
                    spi_imgReadoutCounter <= spi_msgArg[`Msg_Arg_ImgReadout_Counter_Bits];
                    spi_imgReadoutCaptureNext <= spi_msgArg[`Msg_Arg_ImgReadout_CaptureNext_Bits];
                    spi_imgReadoutDone <= 0;
                    spi_state <= SPI_State_ImgOut;
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
                    spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits] <= !spi_imgi2c_done_;
                    spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits] <= imgi2c_status_err;
                    spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits] <= imgi2c_status_readData;
                    spi_state <= SPI_State_RespOut;
                end
                
                `Msg_Type_ImgCaptureStatus: begin
                    // Use `CaptureDone` bit to signal whether we can readout,
                    // not whether the capture has merely been written to RAM
                    spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits] <= spi_imgReadoutReady;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ImageWidth_Bits] <= imgctrl_status_captureImageWidth;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ImageHeight_Bits] <= imgctrl_status_captureImageHeight;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits] <= imgctrl_status_captureHighlightCount;
                    spi_resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits] <= imgctrl_status_captureShadowCount;
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
            
            SPI_State_ImgOut: begin
                spi_d_outEn <= 1;
                if (!spi_doutCounter) begin
                    spi_doutReg <= {spi_imgctrlReadoutData[7:0], spi_imgctrlReadoutData[15:8]}; // Output pixels in little endian
                    spi_imgctrlReadoutTrigger <= 1;
                end
                
                if (spi_imgReadoutDone) begin
                    if (spi_imgReadoutCaptureNext) begin
                        spi_imgCaptureTrigger <= !spi_imgCaptureTrigger;
                    end
                    spi_state <= SPI_State_Nop;
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
            .PIN_TYPE(6'b1101_00),
            .PULLUP(1'b1)
        ) SB_IO_ice_st_spi_d (
            .INPUT_CLK(ice_st_spi_clk),
            .OUTPUT_CLK(ice_st_spi_clk),
            .PACKAGE_PIN(ice_st_spi_d[i]),
            .OUTPUT_ENABLE(spi_d_outEn),
            .D_OUT_0(spi_d_out[i]),
            .D_IN_0(spi_d_in[i])
        );
    end
endmodule







`ifdef SIM
module Testbench();
    reg         ice_img_clk16mhz = 0;
    
    reg         ice_st_spi_clk = 0;
    reg         ice_st_spi_cs_ = 0;
    wire[7:0]   ice_st_spi_d;
    
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
    
    wire[3:0]   ice_led;
    
    Top Top(.*);
    
    localparam ImageWidth = 32;
    localparam ImageHeight = 4;
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
    
    initial begin
        forever begin
            ice_img_clk16mhz = 0;
            #32;
            ice_img_clk16mhz = 1;
            #32;
        end
    end
    
    wire[7:0]   spi_d_out;
    reg         spi_d_outEn = 0;    
    wire[7:0]   spi_d_in;
    assign ice_st_spi_d = (spi_d_outEn ? spi_d_out : {8{1'bz}});
    assign spi_d_in = ice_st_spi_d;
    
    reg[`Msg_Len-1:0] spi_doutReg = 0;
    reg[15:0] spi_dinReg = 0;
    reg[`Resp_Len-1:0] resp = 0;
    reg[((ImageWidth*2)*8)-1:0] imgRow = 0;
    assign spi_d_out[7:4] = `LeftBits(spi_doutReg,0,4);
    assign spi_d_out[3:0] = `LeftBits(spi_doutReg,0,4);
    
    localparam ice_st_spi_clk_HALF_PERIOD = 21;
    
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg, input[31:0] respLen); begin
        reg[15:0] i;
        
        ice_st_spi_cs_ = 0;
        spi_doutReg = {typ, arg};
        spi_d_outEn = 1;
            
            // 2 initial dummy cycles
            for (i=0; i<2; i++) begin
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 1;
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 0;
            end
            
            for (i=0; i<`Msg_Len/4; i++) begin
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 1;
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 0;
                
                spi_doutReg = spi_doutReg<<4|{4{1'b1}};
            end
            
            spi_d_outEn = 0;
            
            // Dummy cycles
            for (i=0; i<4; i++) begin
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 1;
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 0;
            end
            
            // Clock in response
            for (i=0; i<respLen; i++) begin
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 1;
                
                    if (!i[0]) spi_dinReg = 0;
                    spi_dinReg = spi_dinReg<<4|{4'b0000, spi_d_in[3:0], 4'b0000, spi_d_in[7:4]};
                    
                    resp = resp<<8;
                    if (i[0]) resp = resp|spi_dinReg;
                
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 0;
            end
        
        ice_st_spi_cs_ = 1;
        #1; // Allow ice_st_spi_cs_ to take effect
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
    
    task TestImgReset; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n========== TestImgReset ==========");
        
        // ====================
        // Test Img reset
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgReset_Val_Bits] = 0;
        SendMsg(`Msg_Type_ImgReset, arg, 0);
        if (img_rst_ === arg[`Msg_Arg_ImgReset_Val_Bits]) begin
            $display("[STM32] Reset=0 success ✅");
        end else begin
            $display("[STM32] Reset=0 failed ❌");
        end
        
        arg = 0;
        arg[`Msg_Arg_ImgReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_ImgReset, arg, 0);
        if (img_rst_ === arg[`Msg_Arg_ImgReset_Val_Bits]) begin
            $display("[STM32] Reset=1 success ✅");
        end else begin
            $display("[STM32] Reset=1 failed ❌");
        end
    end endtask

    task TestImgStream; begin
        reg[`Msg_Arg_Len-1:0] arg;
        reg[31:0] row;
        reg[31:0] col;
        reg[31:0] i;
        reg[31:0] transferPixelCount;
        $display("\n========== TestImgStream ==========");
        
        arg = 0;
        arg[`Msg_Arg_ImgReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_ImgReset, arg, 0); // Deassert Img reset
        
        arg = 0;
        arg[`Msg_Arg_ImgCapture_DstRAMBlock_Bits] = 0;
        SendMsg(`Msg_Type_ImgCapture, arg, 0);
        
        forever begin
            // Wait until readout is ready
            $display("[STM32] Waiting until readout is ready...");
            do begin
                // Request Img status
                SendMsg(`Msg_Type_ImgCaptureStatus, 0, 8);
            end while(!resp[`Resp_Arg_ImgCaptureStatus_Done_Bits]);
            $display("[STM32] Readout ready ✅ (image size:%0dx%0d, highlightCount:%0d, shadowCount:%0d)",
                resp[`Resp_Arg_ImgCaptureStatus_ImageWidth_Bits],
                resp[`Resp_Arg_ImgCaptureStatus_ImageHeight_Bits],
                resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits],
                resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits],
            );
            
            // 1 pixels     counter=0
            // 2 pixels     counter=2
            // 3 pixels     counter=4
            // 4 pixels     counter=6
            transferPixelCount = 4; // 4 pixels at a time (since `resp` is only 8 bytes=4 pixels wide)
            for (row=0; row<ImageHeight; row++) begin
                for (i=0; i<ImageWidth/transferPixelCount; i++) begin
                    arg[`Msg_Arg_ImgReadout_Counter_Bits] = (transferPixelCount-1)*2;
                    arg[`Msg_Arg_ImgReadout_CaptureNext_Bits] = (row===(ImageHeight-1) && i===((ImageWidth/transferPixelCount)-1));
                    arg[`Msg_Arg_ImgReadout_SrcRAMBlock_Bits] = 0;
                    
                    SendMsg(`Msg_Type_ImgReadout, arg, transferPixelCount*2);
                    imgRow = (imgRow<<(transferPixelCount*2*8))|resp;
                end
                
                $display("Row %04d: %h", row, imgRow);
            end
        end
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
        SendMsg(`Msg_Type_ImgI2CTransaction, arg, 0);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0, 8);
            $display("[STM32] ImgI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[STM32] Write success ✅");
        end else begin
            $display("[STM32] Write failed ❌");
        end
        
        // ====================
        // Test ImgI2C Read (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_2;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h4242;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg, 0);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0, 8);
            $display("[STM32] ImgI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[STM32] Read success ✅");
        end else begin
            $display("[STM32] Read failed ❌");
        end
        
        if (resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits] === 16'hCAFE) begin
            $display("[STM32] Read correct data ✅ (0x%x)", resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
        end else begin
            $display("[STM32] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
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
        SendMsg(`Msg_Type_ImgI2CTransaction, arg, 0);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0, 8);
            $display("[STM32] ImgI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[STM32] Write success ✅");
        end else begin
            $display("[STM32] Write failed ❌");
        end
        
        // ====================
        // Test ImgI2C Read (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_1;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h8484;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg, 0);

        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0, 8);
            $display("[STM32] ImgI2C status: done:%b err:%b readData:0x%x",
                resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );

            done = resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end

        if (!resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[STM32] Read success ✅");
        end else begin
            $display("[STM32] Read failed ❌");
        end

        if ((resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF) === 16'h0037) begin
            $display("[STM32] Read correct data ✅ (0x%x)", resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
        end else begin
            $display("[STM32] Read incorrect data ❌ (0x%x)", resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
        end
    end endtask
    
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        
        // Set our initial state
        ice_st_spi_cs_ = 1;
        spi_doutReg = ~0;
        spi_d_outEn = 0;
        
        // Pulse the clock to get SB_IO initialized
        ice_st_spi_clk = 1;
        #1;
        ice_st_spi_clk = 0;
        
        // TestNoOp();
        // TestEcho();
        
        TestImgReset();
        TestImgStream();
        // TestImgI2CWriteRead();
        
        `Finish;
    end
endmodule
`endif
