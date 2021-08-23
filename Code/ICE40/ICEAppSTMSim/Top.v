`include "../ICEAppSTM/Top.v"          // Before yosys synthesis
// `include "../ICEAppSTM/Synth/Top.v"    // After yosys synthesis
`include "ICEAppTypes.v"
`include "Util.v"

`timescale 1ns/1ps

module Testbench();
    reg         ice_img_clk16mhz = 0;
    
    reg         ice_st_spi_clk = 0;
    reg         ice_st_spi_cs_ = 0;
    wire[7:0]   ice_st_spi_d;
    
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
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        ice_st_spi_cs_ = 0;
        spi_dataOutReg = {typ, arg};
        spi_dataOutEn = 1;
            
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
            
            // Clock in response (if one is sent for this type of message)
            if (typ[`Msg_Type_Resp_Bits]) begin
                for (i=0; i<`Resp_Len; i++) begin
                    #(ice_st_spi_clk_HALF_PERIOD);
                    ice_st_spi_clk = 1;
                
                        if (!i[0]) spi_dinReg = 0;
                        spi_dinReg = spi_dinReg<<4|{4'b0000, spi_dataIn[3:0], 4'b0000, spi_dataIn[7:4]};
                    
                        spi_resp = spi_resp<<8;
                        if (i[0]) spi_resp = spi_resp|spi_dinReg;
                
                    #(ice_st_spi_clk_HALF_PERIOD);
                    ice_st_spi_clk = 0;
                end
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
    
    initial begin
        #1;
        ice_st_spi_cs_ = ~0;
        spi_dataOutReg = ~0;
        spi_dataOutEn = ~0;
        #1
        
        `Finish;
        
        
        TestEcho(56'h00000000000000);
        TestEcho(56'hCAFEBABEFEEDAA);
        TestNop();
        TestEcho(56'hCAFEBABEFEEDAA);
        TestEcho(56'h123456789ABCDE);
        TestNop();
        `Finish;
    end
endmodule
