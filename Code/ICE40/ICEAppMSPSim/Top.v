`include "../ICEAppMSP/Top.v"          // Before yosys synthesis
// `include "../ICEAppMSP/Synth/Top.v"    // After yosys synthesis
`include "ICEAppTypes.v"
`include "Util.v"

// SDCARDSIM_LVS_INIT_IGNORE_5MS: Don't require waiting for 5ms, because that takes way too long in simulation
`define SDCARDSIM_LVS_INIT_IGNORE_5MS
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
        // Only do this if typ!=0. For nop's (typ==0), we don't want to perform these
        // turnaround cycles because we're no longer driving the SPI data line,
        // so the SPI state machine will (correctly) give an error when a SPI clock
        // is supplied but the SPI data line is invalid.
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
    
    task TestImgSetHeader1(input[7:0] version, input[31:0] timestamp, input[15:0] imageWidth); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[Testbench] ========== TestImgSetHeader1 ==========");
        arg = 0;
        arg[55:48] = version;
        arg[47:16] = timestamp;
        arg[15: 0] = imageWidth;
        
        SendMsg(`Msg_Type_ImgSetHeader1, arg);
    end endtask
    
    task TestImgSetHeader2(input[15:0] imageHeight, input[15:0] exposure, input[15:0] gain); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[Testbench] ========== TestImgSetHeader2 ==========");
        arg = 0;
        arg[55:40] = imageHeight;
        arg[39:24] = exposure;
        arg[23: 8] = gain;
        SendMsg(`Msg_Type_ImgSetHeader2, arg);
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
        $display("[Testbench] Capture done ✅ (done:%b image size:%0d, highlightCount:%0d, shadowCount:%0d)",
            spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_WordCount_Bits],
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
        TestImgSetHeader1(8'h42 /* version */, 32'hAABBCCDD /* timestamp */, 16'd2304 /* image width */);
        TestImgSetHeader2(16'd1296 /* image height */, 16'h1111 /* exposure */, 16'h2222 /* gain */);
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
