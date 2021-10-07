`include "../ICEAppSTM/Top.v"          // Before yosys synthesis
// `include "../ICEAppSTM/Synth/Top.v"    // After yosys synthesis
`include "ICEAppTypes.v"
`include "Util.v"
`include "SDCardSim.v"
`include "EndianSwap.v"

`timescale 1ns/1ps

module Testbench();
    `include "ICEAppSim.v"
    
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
    
    EndianSwap #(.Width(16)) SDReadout_HostFromLittle16();
    EndianSwap #(.Width(32)) SDReadout_HostFromLittle32();
    
    task SDReadout(input waitForDReady, input validateWords, input[7:0] wordWidth, input[31:0] wordCount); begin
        parameter WordWidthMin = 16;
        parameter WordWidthMax = 32;
        parameter WordIncrement = -1;
        parameter ChunkLen = 4*4096; // Each chunk consists of 4x RAM4K == 4*4096 bits
        
        $display("\n[Testbench] ========== SDReadout ==========");
        
        if (wordWidth<WordWidthMin || wordWidth>WordWidthMax) begin
            $display("\n[Testbench] SDReadout: invalid wordWidth=%0d", wordWidth);
            `Finish;
        end
        
        ice_st_spi_cs_ = 1;
        #1; // Let ice_st_spi_cs_ take effect
        ice_st_spi_cs_ = 0;
        #1; // Let ice_st_spi_cs_ take effect
        
        begin
            reg[WordWidthMax-1:0] word;
            reg[WordWidthMax-1:0] lastWord;
            reg[WordWidthMax-1:0] expectedWord;
            reg lastWordInit;
            reg[31:0] wordIdx;
            reg[31:0] chunkIdx;
            reg[31:0] chunkCount;
            lastWordInit = 0;
            wordIdx = 0;
            chunkIdx = 0;
            chunkCount = ((wordWidth*wordCount)+(ChunkLen-1)) / ChunkLen;
            
            _SendMsg(`Msg_Type_Readout, 0);
            
            while (wordIdx < wordCount) begin
                reg[15:0] i;
                
                $display("[Testbench] Reading chunk %0d/%0d...", chunkIdx+1, chunkCount);
                
                if (waitForDReady) begin
                    reg done;
                    done = 0;
                    while (!done) begin
                        #2000;
                        $display("[Testbench] Waiting for ice_st_spi_d_ready (%b)...", ice_st_spi_d_ready);
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

                    case (wordWidth)
                    16: word = SDReadout_HostFromLittle16.Swap(spi_resp[15:0]);
                    32: word = SDReadout_HostFromLittle32.Swap(spi_resp[31:0]);
                    endcase
                    
                    // $display("[Testbench] Read word: 0x%x", word);
                    
                    if (lastWordInit) begin
                        expectedWord = lastWord + WordIncrement;
                        if (validateWords && word!==expectedWord) begin
                            $display("[Testbench] Bad word; expected:%x got:%x ❌", expectedWord, word);
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
    
    // TestSDCMD6_CheckAccessMode: required by TestSDCMD6
    task TestSDCMD6_CheckAccessMode; begin
        SDReadout(/* waitForDReady */ 0, /* validateWords */ 0, /* wordWidth */ 16, /* wordCount */ (512/16));
        
        // Check the access mode from the CMD6 response
        if (spi_datIn[379:376] === 4'h3) begin
            $display("[Testbench] CMD6 access mode (expected: 4'h3, got: 4'h%x) ✅", spi_datIn[379:376]);
        end else begin
            $display("[Testbench] CMD6 access mode (expected: 4'h3, got: 4'h%x) ❌", spi_datIn[379:376]);
            `Finish;
        end
    end endtask
    
    // TestSDDatIn_Readout: required by TestSDDatIn
    task TestSDDatIn_Readout; begin
        SDReadout(/* waitForDReady */ 1, /* validateWords */ 1, /* wordWidth */ 32, /* wordCount */ 4*1024);
    end endtask
    
    initial begin
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
        TestSDCMD2();
        TestSDCMD6();
        //           delay, speed,                            trigger, reset
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Fast, 0,       0);
        
        TestSDDatIn();
        TestLEDSet(4'b1010);
        TestSDDatIn();
        
        `Finish;
    end
endmodule
