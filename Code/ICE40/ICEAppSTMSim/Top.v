// SD_LVS_SHORT_INIT: When simulating, don't require waiting the full 5ms when initializing
// the SD card, because it takes a long time to simulate
`ifdef SIM
`define SD_LVS_SHORT_INIT
`endif

`include "../ICEAppSTM/Top.v"          // Before yosys synthesis
// `include "../ICEAppSTM/Synth/Top.v"    // After yosys synthesis
`include "ICEAppTypes.v"
`include "Util.v"
`include "SDCardSim.v"

`timescale 1ns/1ps

module Testbench();
    reg         ice_img_clk16mhz = 0;
    
    wire        sd_clk;
    wire        sd_cmd;
    wire[3:0]   sd_dat;
    
    reg         ice_st_spi_clk = 0;
    reg         ice_st_spi_cs_ = 1;
    wire[7:0]   ice_st_spi_d;
    wire        ice_st_spi_d_ready;
    wire        ice_st_spi_d_ready_rev4bodge;
    
    wire[3:0]   ice_led;
    
    Top Top(.*);
    
    SDCardSim SDCardSim(
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    initial begin
        forever begin
            ice_img_clk16mhz = ~ice_img_clk16mhz;
            #32;
        end
    end
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    wire[7:0]   spi_dataOut;
    reg         spi_dataOutEn = 0;    
    wire[7:0]   spi_dataIn;
    assign ice_st_spi_d = (spi_dataOutEn ? spi_dataOut : {8{1'bz}});
    assign spi_dataIn = ice_st_spi_d;
    
    reg[`Msg_Len-1:0] spi_dataOutReg = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    reg[511:0] spi_datIn = 0;
    
    reg[15:0] spi_dinReg = 0;
    assign spi_dataOut[7:4] = `LeftBits(spi_dataOutReg,0,4);
    assign spi_dataOut[3:0] = `LeftBits(spi_dataOutReg,0,4);
    
    localparam ice_st_spi_clk_HALF_PERIOD = 8; // 64 MHz
    
    task _SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        spi_dataOutReg = {typ, arg};
        spi_dataOutEn = 1;
            
            // 2 initial dummy cycles
            for (i=0; i<2; i++) begin
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 1;
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 0;
            end
            
            // Clock out message
            for (i=0; i<`Msg_Len/4; i++) begin
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 1;
                #(ice_st_spi_clk_HALF_PERIOD);
                ice_st_spi_clk = 0;
                
                spi_dataOutReg = spi_dataOutReg<<4|{4{1'b1}};
            end
            
            spi_dataOutEn = 0;
            
            // Turnaround delay cycles
            // Only do this if typ!=0. For nop's (typ==0), we don't want to perform these
            // turnaround cycles because we're no longer driving the SPI data line,
            // so the SPI state machine will (correctly) give an error when a SPI clock
            // is supplied but the SPI data line is invalid.
            if (typ !== 0) begin
                for (i=0; i<4; i++) begin
                    #(ice_st_spi_clk_HALF_PERIOD);
                    ice_st_spi_clk = 1;
                    #(ice_st_spi_clk_HALF_PERIOD);
                    ice_st_spi_clk = 0;
                end
            end
        
    end endtask
    
    task _ReadResp(input[31:0] len); begin
        reg[15:0] i;
        // Clock in response (if one is sent for this type of message)
        for (i=0; i<len/8; i++) begin
                if (!i[0]) spi_dinReg = 0;
                spi_dinReg = spi_dinReg<<4|{4'b0000, spi_dataIn[3:0], 4'b0000, spi_dataIn[7:4]};
                
                spi_resp = spi_resp<<8;
                if (i[0]) spi_resp = spi_resp|spi_dinReg;
            
            #(ice_st_spi_clk_HALF_PERIOD);
            ice_st_spi_clk = 1;
            
            #(ice_st_spi_clk_HALF_PERIOD);
            ice_st_spi_clk = 0;
        end
    end endtask
    
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        ice_st_spi_cs_ = 0;
            
            _SendMsg(typ, arg);
            
            // Clock in response (if one is sent for this type of message)
            if (typ[`Msg_Type_Resp_Bits]) begin
                _ReadResp(`Resp_Len);
            end
        
        ice_st_spi_cs_ = 1;
        #1; // Allow ice_st_spi_cs_ to take effect
    
    end endtask
    
    task TestNop; begin
        $display("\n[Testbench] ========== TestNop ==========");
        SendMsg(`Msg_Type_Nop, 56'h123456789ABCDE);
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
    localparam CMD18    = 6'd18;    // READ_MULTIPLE_BLOCK
    localparam CMD25    = 6'd25;    // WRITE_MULTIPLE_BLOCK
    localparam CMD41    = 6'd41;    // SD_SEND_BIT_OP_COND
    localparam CMD55    = 6'd55;    // APP_CMD
    localparam ACMD23   = 6'd23;    // SET_WR_BLK_ERASE_COUNT
    
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
            if (respType !== `SDController_RespType_None) done &= spi_resp[`Resp_Arg_SDStatus_RespDone_Bits];
            if (datInType === `SDController_DatInType_512x1) done &= spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits];
            
            // Our clock is much faster than the SD slow clock (64 MHz vs .4 MHz),
            // so wait a bit before asking for the status again
            #(50_000);
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
        input[`Msg_Arg_SDInit_Reset_Len-1:0] reset
    ); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        // $display("\n[Testbench] ========== TestSDConfig ==========");
        arg[`Msg_Arg_SDInit_Clk_Delay_Bits] = delay;
        arg[`Msg_Arg_SDInit_Clk_Speed_Bits] = speed;
        arg[`Msg_Arg_SDInit_Trigger_Bits] = trigger;
        arg[`Msg_Arg_SDInit_Reset_Bits] = reset;
        
        SendMsg(`Msg_Type_SDInit, arg);
    end endtask
    
    task TestSDInit; begin
        reg[15:0] i;
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;
        
        $display("\n[Testbench] ========== TestSDInit ==========");
        
        //           delay, speed,                            trigger, reset
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
        #((10*1e9)/400e3); // Wait 10 400kHz cycles
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 0,       0);
        #((10*1e9)/400e3); // Wait 10 400kHz cycles
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 0,       1);
        #((10*1e9)/400e3); // Wait 10 400kHz cycles
        // <-- Turn on power to SD card
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 1,       0);
        
`ifdef SD_LVS_SHORT_INIT
        // Wait 50us, because waiting 5ms takes forever in simulation
        $display("[Testbench] Waiting 50us (and pretending it's 5ms)...");
        #(50_000);
`else
        // Wait 5ms
        $display("[Testbench] Waiting 5ms...");
        #(5_000_000);
`endif
        $display("[Testbench] 5ms elapsed");
        
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
        SendSDCmdResp(CMD0, `SDController_RespType_None, `SDController_DatInType_None, 0);
    end endtask
    
    task TestSDCMD8; begin
        // ====================
        // Test SD CMD8 (SEND_IF_COND)
        // ====================
        reg[`Resp_Arg_SDStatus_Resp_Len-1:0] sdResp;
        
        $display("\n[Testbench] ========== TestSDCMD8 ==========");
        
        // Send SD CMD8
        SendSDCmdResp(CMD8, `SDController_RespType_48, `SDController_DatInType_None, 32'h000001AA);
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
    
    task SDReadout(input waitForDReady, input validateWords, input[7:0] wordWidth, input[31:0] wordCount); begin
        parameter MinWordWidth = 16;
        parameter MaxWordWidth = 32;
        parameter ChunkLen = 4*4096; // Each chunk consists of 4x RAM4K == 4*4096 bits
        
        $display("\n[Testbench] ========== SDReadout ==========");
        
        if (wordWidth<MinWordWidth || wordWidth>MaxWordWidth) begin
            $display("\n[Testbench] SDReadout: invalid wordWidth=%0d", wordWidth);
            `Finish;
        end
        
        ice_st_spi_cs_ = 1;
        #1; // Let ice_st_spi_cs_ take effect
        ice_st_spi_cs_ = 0;
        #1; // Let ice_st_spi_cs_ take effect
        
        begin
            reg[MaxWordWidth-1:0] word;
            reg[MaxWordWidth-1:0] lastWord;
            reg[MaxWordWidth-1:0] expectedWord;
            reg lastWordInit;
            reg[31:0] wordIdx;
            reg[31:0] chunkIdx;
            reg[31:0] chunkCount;
            lastWordInit = 0;
            wordIdx = 0;
            chunkIdx = 0;
            chunkCount = ((wordWidth*wordCount)+(ChunkLen-1)) / ChunkLen;
            
            _SendMsg(`Msg_Type_SDReadout, 0);
            
            while (wordIdx < wordCount) begin
                reg[15:0] i;
                
                $display("Reading chunk %0d/%0d...", chunkIdx+1, chunkCount);
                
                if (waitForDReady) begin
                    reg done;
                    done = 0;
                    while (!done) begin
                        #2000;
                        $display("Waiting for ice_st_spi_d_ready (%b)...", ice_st_spi_d_ready);
                        if (ice_st_spi_d_ready) begin
                            done = 1;
                        end
                    end
                end
                
                #100; // TODO: remove; this helps debug where 8 dummy cycles start
                
                // Dummy cycles
                for (i=0; i<8; i++) begin
                    #(ice_st_spi_clk_HALF_PERIOD);
                    ice_st_spi_clk = 1;
                    #(ice_st_spi_clk_HALF_PERIOD);
                    ice_st_spi_clk = 0;
                end
                
                #100; // TODO: remove; this helps debug where 8 dummy cycles end
                
                for (i=0; i<(ChunkLen/wordWidth) && (wordIdx<wordCount); i++) begin
                    spi_resp = 0;
                    _ReadResp(wordWidth);
                    word = spi_resp[MaxWordWidth-1:0];
                    $display("Read word: 0x%x", word);
                    
                    if (lastWordInit) begin
                        // expectedWord = lastWord+1;   // Expect incrementing integers
                        expectedWord = lastWord-1;   // Expect decrementing integers
                        if (validateWords && word!==expectedWord) begin
                            $display("Bad word; expected:%x got:%x ❌", expectedWord, word);
                            #100;
                            `Finish;
                        end
                    end
                    
                    spi_datIn = spi_datIn<<wordWidth;
                    spi_datIn |= word;
                    
                    lastWord = word;
                    lastWordInit = 1;
                    wordIdx++;
                end
                
                chunkIdx++;
            end
        end
        
        ice_st_spi_cs_ = 1;
        #1; // Let ice_st_spi_cs_ take effect
        
        $display("[Testbench] SDReadout OK ✅");
    end endtask
    
    task TestSDDatIn; begin
        $display("\n[Testbench] ========== TestSDDatIn ==========");
        
        // Send SD command CMD18 (READ_MULTIPLE_BLOCK)
        SendSDCmdResp(CMD18, `SDController_RespType_48, `SDController_DatInType_4096xN, 32'b0);
        
        SDReadout(/* waitForDReady */ 1, /* validateWords */ 1, /* wordWidth */ 32, /* wordCount */ 128*1024);
    end endtask
    
    task TestSDCMD6; begin
        // ====================
        // Test CMD6 (SWITCH_FUNC) + DatIn
        // ====================
        
        $display("\n[Testbench] ========== TestSDCMD6 ==========");
        
        // Send SD command CMD6 (SWITCH_FUNC)
        SendSDCmdResp(CMD6, `SDController_RespType_48, `SDController_DatInType_512x1, 32'h80FFFFF3);
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
        
        SDReadout(/* waitForDReady */ 0, /* validateWords */ 0, /* wordWidth */ 16, /* wordCount */ (512/16));
        
        // Check the access mode from the CMD6 response
        if (spi_datIn[379:376] === 4'h3) begin
            $display("[Testbench] CMD6 access mode (expected: 4'h3, got: 4'h%x) ✅", spi_datIn[379:376]);
        end else begin
            $display("[Testbench] CMD6 access mode (expected: 4'h3, got: 4'h%x) ❌", spi_datIn[379:376]);
            // `Finish;
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
        SendSDCmdResp(CMD2, `SDController_RespType_136, `SDController_DatInType_None, 0);
        $display("[Testbench] ====================================================");
        $display("[Testbench] ^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        $display("[Testbench] ====================================================");
    end endtask
    
    initial begin
        // // Pulse the clock to get Top's SB_IO initialized.
        // // This is necessary because because its OUTPUT_ENABLE is x
        // // This is necessary because
        // spi_dataOutEn   = 1; #1;
        // ice_st_spi_clk  = 1; #1;
        // ice_st_spi_clk  = 0; #1;
        // spi_dataOutEn   = 0; #1;
        
        TestEcho(56'h00000000000000);
        TestEcho(56'h00000000000000);
        TestEcho(56'hCAFEBABEFEEDAA);
        TestNop();
        TestEcho(56'hCAFEBABEFEEDAA);
        TestEcho(56'h123456789ABCDE);
        TestLEDSet(4'b1010);
        TestLEDSet(4'b0101);
        TestNop();
        
        TestSDInit();
        TestSDCMD0();
        TestSDCMD8();
        TestSDCMD6();
        //           delay, speed,                            trigger, reset
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Fast, 0,       0);
        
        TestSDDatIn();
        
        
        
        
        
        // SDReadout;
        // TestLEDSet(4'b1111);
        // SDReadout;
        // SDReadout;
        
        // `Finish;
    end
endmodule
