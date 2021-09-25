// SD_LVS_SHORT_INIT: When simulating, don't require waiting the full 5ms when initializing
// the SD card, because it takes a long time to simulate
`ifdef SIM
`define SD_LVS_SHORT_INIT
`endif

`include "../ICEAppMSP/Top.v"          // Before yosys synthesis
// `include "../ICEAppMSP/Synth/Top.v"    // After yosys synthesis
`include "ICEAppTypes.v"
`include "Util.v"
`include "SDCardSim.v"
`include "ImgSim.v"
`include "ImgI2CSlaveSim.v"

// // MOBILE_SDR_INIT_VAL: Initialize the memory because ImgController reads a few words
// // beyond the image that's written to the RAM, and we don't want to read `x` (don't care)
// // when that happens
`define MOBILE_SDR_INIT_VAL 16'hCAFE
`include "mt48h32m16lf/mobile_sdr.v"

`timescale 1ns/1ps

module Testbench();
    `include "ICEAppSim.v"
    
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
    
    SDCardSim #(
        .RecvHeaderWordCount(ImageHeaderWordCount),
        .RecvWordCount(ImageWidth*ImageHeight),
        .RecvWordInitialValue(16'h0FFF),
        .RecvWordDelta(-1)
    ) SDCardSim (
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
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
        // Only do this if typ!=0. For nop's (typ==0), we don't want to perform these
        // turnaround cycles because we're no longer driving the SPI data line,
        // so the SPI state machine will (correctly) give an error (in simulation)
        // when a SPI clock is supplied but the SPI data line is invalid.
        if (typ !== 0) begin
            for (i=0; i<8; i++) begin
                #(ice_msp_spi_clk_HALF_PERIOD);
                ice_msp_spi_clk = 1;
                #(ice_msp_spi_clk_HALF_PERIOD);
                ice_msp_spi_clk = 0;
            end
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
        
        spi_dataOutReg = 0;
        spi_dataOutEn = 1;
        
        $display("[Testbench] ice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #20000;
        
        if (sim_rst_ === 1'b1) begin
            $display("[Testbench] sim_rst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b1 ❌ (%b)", sim_rst_);
            // `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 1");
        ice_msp_spi_clk = 1;
        #20000;
        
        if (sim_rst_ === 1'b0) begin
            $display("[Testbench] sim_rst_ === 1'b0 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b0 ❌ (%b)", sim_rst_);
            // `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #20000;
        
        if (sim_rst_ === 1'b1) begin
            $display("[Testbench] sim_rst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b1 ❌ (%b)", sim_rst_);
            // `Finish;
        end
        
        spi_dataOutEn = 0;
        
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
    
    // TestSDCheckCMD6AccessMode: required by TestSDCMD6
    task TestSDCMD6_CheckAccessMode; begin
        // Check the access mode from the CMD6 response
        if (spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits] === 4'h3) begin
            $display("[Testbench] CMD6 access mode == 0x3 ✅");
        end else begin
            $display("[Testbench] CMD6 access mode == 0x%h ❌", spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits]);
            `Finish;
        end
    end endtask
    
    // TestSDDatIn_Readout: required by TestSDDatIn
    task TestSDDatIn_Readout; begin
        $display("[Testbench] ICEAppMSP doesn't support SD DatIn");
        `Finish;
    end endtask
    
    initial begin
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
        TestImgSetHeader(0, {16'h4242 /* version */, 16'd2304 /* image width */, 16'd1296 /* image height */, 8'b0 /* padding */});
        TestImgSetHeader(1, {32'hCAFEBABE /* counter */, 24'b0 /* padding */});
        TestImgSetHeader(2, {32'hDEADBEEF /* timestamp */, 24'b0 /* padding */});
        TestImgSetHeader(3, {16'h1111 /* exposure */, 16'h2222 /* gain */, 24'b0 /* padding */});
        // TestImgI2CWriteRead();
        TestImgCapture();
        
        // TestSDInit();
        // TestSDCMD0();
        // TestSDCMD8();
        // TestSDCMD2();
        // TestSDCMD6();
        // //           delay, speed,                            trigger, reset
        // TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
        // TestSDConfig(0,     `SDController_Init_ClkSpeed_Fast, 0,       0);
        //
        // TestSDRespRecovery();
        // TestSDDatOut();
        // TestSDDatOutRecovery();
        
        `Finish;
    end
endmodule
