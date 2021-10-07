`include "../ICEAppMSP/Top.v"          // Before yosys synthesis
`include "ICEAppTypes.v"
`include "Util.v"
`include "SDCardSim.v"
`include "ImgSim.v"
`include "ImgI2CSlaveSim.v"

// MOBILE_SDR_INIT_VAL: Initialize the memory because ImgController reads a few words
// beyond the image that's written to the RAM, and we don't want to read `x` (don't care)
// when that happens
`define MOBILE_SDR_INIT_VAL 16'hCAFE
`include "mt48h32m16lf/mobile_sdr.v"

`timescale 1ns/1ps

module Testbench();
    `include "ICEAppSim.v"
    
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
        
        if (sim_spiRst_ === 1'b1) begin
            $display("[Testbench] sim_spiRst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_spiRst_ !== 1'b1 ❌ (%b)", sim_spiRst_);
            `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 1");
        ice_msp_spi_clk = 1;
        #20000;
        
        if (sim_spiRst_ === 1'b0) begin
            $display("[Testbench] sim_spiRst_ === 1'b0 ✅");
        end else begin
            $display("[Testbench] sim_spiRst_ !== 1'b0 ❌ (%b)", sim_spiRst_);
            `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #20000;
        
        if (sim_spiRst_ === 1'b1) begin
            $display("[Testbench] sim_spiRst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_spiRst_ !== 1'b1 ❌ (%b)", sim_spiRst_);
            `Finish;
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
    
    EndianSwap #(.Width(16)) LittleFromHost16();
    EndianSwap #(.Width(32)) LittleFromHost32();
    
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
        TestImgSetHeader(0, {
            LittleFromHost16.Swap(16'h4242)     /* version      */,
            LittleFromHost16.Swap(16'd2304)     /* image width  */,
            LittleFromHost16.Swap(16'd1296)     /* image height */
        });
        
        TestImgSetHeader(1, {
            LittleFromHost32.Swap(32'hCAFEBABE) /* counter      */,
            LittleFromHost16.Swap(16'b0)        /* padding      */
        });
        
        TestImgSetHeader(2, {
            LittleFromHost32.Swap(32'hDEADBEEF) /* timestamp    */,
            LittleFromHost16.Swap(16'b0)        /* padding      */
        });
        
        TestImgSetHeader(3, {
            LittleFromHost16.Swap(16'h1111)     /* exposure     */,
            LittleFromHost16.Swap(16'h2222)     /* gain         */,
            LittleFromHost16.Swap(16'b0)        /* padding      */
        });
        
        // TestImgI2CWriteRead();
        TestImgCapture();
        
        TestSDInit();
        // TestSDCMD0();
        // TestSDCMD8();
        // TestSDCMD2();
        // TestSDCMD6();
        //           delay, speed,                            trigger, reset
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Fast, 0,       0);
        
        // TestSDRespRecovery();
        TestSDDatOut();
        // TestSDDatOutRecovery();
        
        `Finish;
    end
endmodule
