`include "../ICEAppSTM/Top.v"          // Before yosys synthesis
// `include "../ICEAppSTM/Synth/Top.v"    // After yosys synthesis
`include "ICEAppTypes.v"
`include "Util.v"

`timescale 1ns/1ps

module Testbench();
    reg         ice_img_clk16mhz = 0;
    
    reg         ice_st_spi_clk = 0;
    reg         ice_st_spi_cs_ = 1;
    wire[7:0]   ice_st_spi_d;
    wire        ice_st_spi_d_ready;
    wire        ice_st_spi_d_ready_rev4bodge;
    
    wire[3:0]   ice_led;
    
    Top Top(.*);
    
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
            #(ice_st_spi_clk_HALF_PERIOD);
            ice_st_spi_clk = 1;
            
                if (!i[0]) spi_dinReg = 0;
                spi_dinReg = spi_dinReg<<4|{4'b0000, spi_dataIn[3:0], 4'b0000, spi_dataIn[7:4]};
                
                spi_resp = spi_resp<<8;
                if (i[0]) spi_resp = spi_resp|spi_dinReg;
            
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
    
    task TestSDReadout; begin
        reg[7:0] word;
        reg[7:0] lastWord;
        reg[7:0] expectedWord;
        reg lastWordInit;
        
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;
        reg[15:0] i;
        reg[15:0] chunkIdx;
        parameter ChunkLen = 4096*4; // Each chunk consists of 4x RAM4K
        parameter WordLen = 16;
        parameter ChunkCount = 4; // Number of chunks to read
        
        $display("\n[Testbench] ========== TestSDReadout ==========");
        arg = 0;
        
        ice_st_spi_cs_ = 0;
        
            _SendMsg(`Msg_Type_SDReadout, arg);
            
            lastWordInit = 0;
            for (chunkIdx=0; chunkIdx<ChunkCount; chunkIdx++) begin
                $display("Reading chunk %0d/%0d...", chunkIdx+1, ChunkCount);
                
                done = 0;
                while (!done) begin
                    #2000;
                    $display("Waiting for ice_st_spi_d_ready (%b)...", ice_st_spi_d_ready);
                    if (ice_st_spi_d_ready) begin
                        done = 1;
                    end
                end
                
                // Dummy cycles (8)
                _ReadResp(8*8);
                
                for (i=0; i<(ChunkLen/WordLen); i++) begin
                    _ReadResp(WordLen);
                    
                    word = spi_resp[WordLen  -1 -: 8];
                    // $display("Read word: %x", word);
                    
                    if (lastWordInit) begin
                        expectedWord = lastWord+1;
                        if (word !== expectedWord) begin
                            $display("Bad word; expected:%x got:%x ❌", expectedWord, word);
                            #100;
                            `Finish;
                        end
                    end
                    
                    lastWord = word;
                    lastWordInit = 1;
                    word = spi_resp[WordLen-8-1 -: 8];
                    // $display("Read word: %x", word);
                    
                    expectedWord = lastWord+1;
                    if (word !== expectedWord) begin
                        $display("Bad word; expected:%x got:%x ❌", expectedWord, word);
                        #100;
                        `Finish;
                    end
                    
                    lastWord = word;
                    // `Finish;
                end
            end
        
        ice_st_spi_cs_ = 1;
        #1; // Let ice_st_spi_cs_ take effect
        
        $display("[Testbench] TestSDReadout OK ✅");
        
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
        
        TestSDReadout;
        TestLEDSet(4'b1111);
        TestSDReadout;
        TestSDReadout;
        
        `Finish;
    end
endmodule
