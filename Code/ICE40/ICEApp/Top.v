`include "Util.v"
`include "Sync.v"
`include "ToggleAck.v"
`include "ICEAppTypes.v"
`include "ClockGen.v"
`include "ImgController.v"
`include "ImgI2CMaster.v"

`ifdef SIM
`include "ImgSim.v"
`include "ImgI2CSlaveSim.v"

// MOBILE_SDR_INIT_VAL: Initialize the memory because ImgController reads a few words
// beyond the image that's written to the RAM, and we don't want to read `x` (don't care)
// when that happens
`define MOBILE_SDR_INIT_VAL 16'hCAFE
`include "mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    input wire          ice_msp_spi_clk,
    inout wire          ice_msp_spi_data,
    
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
        
        // Clock in response
        for (i=0; i<`Resp_Len; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            
                spi_resp = spi_resp<<1|spi_dataIn;
            
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
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
        if (spi_resp === 64'hxxxxxxxxxxxxxxxx) begin
            $display("[Testbench] Response OK: %h ✅", spi_resp);
        end else begin
            $display("[Testbench] Bad response: %h ❌", spi_resp);
            `Finish;
        end
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
        TestImgCapture();
        
        `Finish;
    end
endmodule
`endif
