`define SYNTH
`timescale 1ns/1ps
`include "SDRAMController.v"

//module Random9(
//    input logic next, rst,
//    output logic[8:0] q
//);
//    always @(posedge next, negedge next)
//        if (rst) q <= 1;
//        // Feedback polynomial for N=9: x^9 + x^5 + 1
//        else q <= {q[7:0], q[9-1] ^ q[5-1]};
//endmodule
//
//module Random16(
//    input logic next, rst,
//    output logic[15:0] q
//);
//    always @(posedge next, negedge next)
//        if (rst) q <= 1;
//        // Feedback polynomial for N=16: x^16 + x^15 + x^13 + x^4 + 1
//        else q <= {q[14:0], q[16-1] ^ q[15-1] ^ q[13-1] ^ q[4-1]};
//endmodule
//
//module Random23(
//    input logic next, rst,
//    output logic[22:0] q
//);
//    always @(posedge next, negedge next)
//        if (rst) q <= 1;
//        // Feedback polynomial for N=23: x^23 + x^18 + 1
//        else q <= {q[21:0], q[23-1] ^ q[18-1]};
//endmodule

module Random9(
    input logic clk, rst, next,
    output logic[8:0] q
);
    always @(posedge clk)
        if (rst) q <= 0;
        else if (next) q <= q+1;
endmodule

module Random16(
    input logic clk, rst, next,
    output logic[15:0] q
);
    always @(posedge clk)
        if (rst) q <= 0;
        else if (next) q <= q+1;
endmodule

module Random23(
    input logic clk, rst, next,
    output logic[22:0] q
);
    always @(posedge clk)
        if (rst) q <= 0;
        else if (next) q <= q+1;
endmodule

function [15:0] DataFromAddress;
    input [22:0] addr;
//    DataFromAddress = {9'h1B5, addr[22:16]} ^ ~(addr[15:0]);
//    DataFromAddress = addr[22:7];
    DataFromAddress = addr[15:0];
//    DataFromAddress = 0;
endfunction

module IceboardTest_SDRAMReadWriteRandomly(
    input logic         clk12mhz,
    
    output logic[7:0]   leds,
    
    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_udqm,
    output logic        sdram_ldqm,
    inout logic[15:0]   sdram_dq
);
    `define RESET_BIT 26
    
    logic[`RESET_BIT:0] clkDivider;
    always @(posedge clk12mhz) clkDivider <= clkDivider+1;
    
    `ifndef SYNTH
    initial clkDivider = 0;
    `endif
    
    logic clk;
    
//    localparam ClockFrequency = 12000000;       // 12 MHz
//    assign clk = clk12mhz;
//    
//    localparam ClockFrequency =  6000000;     // 6 MHz
//    assign clk = clkDivider[0];
//
//    localparam ClockFrequency =  3000000;     // 3 MHz
//    assign clk = clkDivider[1];
//
    localparam ClockFrequency =  1500000;     // 1.5 MHz
    assign clk = clkDivider[2];
//
//    localparam ClockFrequency =   750000;     // .75 MHz
//    assign clk = clkDivider[3];
    
    // Generate our own reset signal
    // This relies on the fact that the ice40 FPGA resets flipflops to 0 at power up
    logic[12:0] rstCounter;
    logic rst;
    logic lastBit;
    assign rst = !rstCounter[$size(rstCounter)-1];
    always @(posedge clk) begin
        if (rst) begin
            rstCounter <= rstCounter+1;
        end
    end
    
    `ifndef SYNTH
    initial rstCounter = 0;
    `endif
    
    localparam AddrWidth = 23;
    localparam AddrCount = 'h800000;
    localparam AddrCountLimit = AddrCount;
//    localparam AddrCountLimit = AddrCount/1024; // 32k words
//    localparam AddrCountLimit = AddrCount/8192; // 1k words
    localparam DataWidth = 16;
    localparam MaxEnqueuedReads = 10;
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    
    localparam ModeIdle     = 2'h0;
    localparam ModeRead     = 2'h1;
    
    logic                   cmdReady;
    logic                   cmdTrigger;
    logic[AddrWidth-1:0]    cmdAddr;
    logic                   cmdWrite;
    logic[DataWidth-1:0]    cmdWriteData;
    logic[DataWidth-1:0]    cmdReadData;
    logic                   cmdReadDataValid;
    
    logic needInit;
    logic status;
    logic[(AddrWidth*MaxEnqueuedReads)-1:0] enqueuedReadAddrs;
    logic[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount;
    
    logic[AddrWidth-1:0] currentReadAddr;
    assign currentReadAddr = enqueuedReadAddrs[AddrWidth-1:0];
    
    logic[1:0] mode;
    logic[AddrWidth-1:0] modeCounter;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        .rst(rst),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_udqm(sdram_udqm),
        .sdram_ldqm(sdram_ldqm),
        .sdram_dq(sdram_dq)
    );
    
    logic[8:0] random9;
    logic random9Next;
    Random9 random9Gen(.clk(clk), .rst(rst), .next(random9Next), .q(random9));
    
    logic[15:0] random16;
    logic random16Next;
    Random16 random16Gen(.clk(clk), .rst(rst), .next(random16Next), .q(random16));
    
    logic[22:0] random23;
    logic random23Next;
    Random23 random23Gen(.clk(clk), .rst(rst), .next(random23Next), .q(random23));
    
    logic[22:0] randomAddr;
    assign randomAddr = random23&(AddrCountLimit-1);
    
    // Show the 4 debug bytes on our LEDs
    logic[63:0] debugData;
    logic[3:0] debugState;
    
    always @(posedge rst, posedge clkDivider[23]) begin
        if (rst) begin
            debugState <= 0;
            leds <= 0;
        
        end else if (status != StatusOK) begin
            debugState <= debugState+1;
            case (debugState)
            0:          leds <= 8'b11111111;
            1:          leds <= 8'b00000000;
            2:          leds <= 8'b11111111;
            3:          leds <= 8'b00000000;
            
            4:          leds <= debugData[64-1 -: 8];
            5:          leds <= debugData[56-1 -: 8];
            6:          leds <= debugData[48-1 -: 8];
            7:          leds <= debugData[40-1 -: 8];
            
            8:          leds <= 8'b11110000;
            9:          leds <= 8'b00001111;
            10:         leds <= 8'b11110000;
            11:         leds <= 8'b00001111;
            
            12:         leds <= debugData[32-1 -: 8];
            13:         leds <= debugData[24-1 -: 8];
            14:         leds <= debugData[16-1 -: 8];
            15:         leds <= debugData[ 8-1 -: 8];
            endcase
        end
    end
    
    always @(posedge clk) begin
        // Set our default state
        if (cmdReady) cmdTrigger <= 0;
        
        random9Next <= 0;
        random16Next <= 0;
        random23Next <= 0;
        
        if (rst) begin
            needInit <= 1;
            status <= StatusOK;
            
            cmdTrigger <= 0;
            cmdAddr <= 0;
            cmdWrite <= 0;
            cmdWriteData <= 0;
            
            enqueuedReadAddrs <= 0;
            enqueuedReadCount <= 0;
            
            mode <= ModeIdle;
            modeCounter <= 0;
            
            debugData <= 0;
        
        // Initialize memory to known values
        end else if (needInit) begin
            if (!cmdWrite) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= DataFromAddress(0);
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
                if (cmdAddr < AddrCountLimit-1) begin
//                if (cmdAddr < 'h7FFFFF) begin
//                if (cmdAddr < 'hFF) begin
                    cmdTrigger <= 1;
                    cmdAddr <= cmdAddr+1;
                    cmdWrite <= 1;
                    cmdWriteData <= DataFromAddress(cmdAddr+1);
                    
                    `ifndef SYNTH
                        if (!(cmdAddr % 'h1000)) begin
                            $display("Initializing memory: %h", cmdAddr);
                        end
                    `endif
                
                end else begin
                    // Next stage
//                    leds <= 8'b10000000;
                    needInit <= 0;
                end
            end
        
        end else if (status == StatusOK) begin
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    // Verify that the data read out is what we expect
                    if (cmdReadData !== DataFromAddress(currentReadAddr)) begin
                        `ifndef SYNTH
                            $error("Read invalid data (wanted: 0x%h, got: 0x%h)", DataFromAddress(currentReadAddr), cmdReadData);
                        `endif
                        
                        status <= StatusFailed;
                        debugData[63:32] <= {9'b0, currentReadAddr};
                        debugData[31:0] <= {16'b0, cmdReadData};
                        
//                        leds <= 8'b00000001;
//                        leds <= cmdReadData[7:0] | 8'b1;
//                        leds <= cmdReadData[15:8] | cmdReadData[7:0] | 8'b1;
//                        leds <= cmdReadData[15:8];
//                        leds <= cmdReadData[7:0];
//                        leds <= {1'b0, currentReadAddr[22:16]};
//                        leds <= currentReadAddr[15:8];
//                        leds <= currentReadAddr[7:0];
                    end
                    
                    enqueuedReadAddrs <= enqueuedReadAddrs >> AddrWidth;
                    enqueuedReadCount <= enqueuedReadCount-1;
                
                // Something's wrong if we weren't expecting data and we got some
                end else begin
                    `ifndef SYNTH
                        $error("Received data when we didn't expect any");
                    `endif
                    
                    status <= StatusFailed;
                    debugData <= 0;
                end
            end
            
            // Current command was accepted: prepare a new command
            else if (cmdReady) begin
                case (mode)
                // We're idle: accept a new mode
                ModeIdle: begin
                    // Read
                    if (random16 < 3*'h3333) begin
                        `ifndef SYNTH
                            $display("Read: %h", randomAddr);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 0;
                        
                        enqueuedReadAddrs <= enqueuedReadAddrs|(randomAddr<<(AddrWidth*enqueuedReadCount));
                        enqueuedReadCount <= enqueuedReadCount+1;
                        
                        mode <= ModeIdle;
                        random23Next <= 1;
                    end
                    
                    // Read sequential (start)
                    else begin
                        `ifndef SYNTH
                            $display("ReadSeq: %h[%h]", randomAddr, random9);
                        `endif
                        
                        cmdTrigger <= 1;
                        cmdAddr <= randomAddr;
                        cmdWrite <= 0;
                        
                        enqueuedReadAddrs <= enqueuedReadAddrs|(randomAddr<<(AddrWidth*enqueuedReadCount));
                        enqueuedReadCount <= enqueuedReadCount+1;
                        
                        mode <= ModeRead;
                        modeCounter <= (AddrCountLimit-randomAddr-1 < random9 ? AddrCountLimit-randomAddr-1 : random9);
                        random9Next <= 1;
                        random23Next <= 1;
                    end
                    
                    random16Next <= 1;
                end
                
                // Read (continue)
                ModeRead: begin
                    if (modeCounter > 0) begin
                        cmdTrigger <= 1;
                        cmdAddr <= cmdAddr+1;
                        cmdWrite <= 0;
                        
                        enqueuedReadAddrs <= enqueuedReadAddrs|((cmdAddr+1)<<(AddrWidth*enqueuedReadCount));
                        enqueuedReadCount <= enqueuedReadCount+1;
                        
                        modeCounter <= modeCounter-1;
                    
                    end else mode <= ModeIdle;
                end
                endcase
            end
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"
`include "4012mt48lc16m16a2/mt48lc16m16a2.v"

module IceboardTest_SDRAMReadWriteRandomlySim(
    output logic[7:0]   leds,

    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_udqm,
    output logic        sdram_ldqm,
    inout logic[15:0]   sdram_dq
);

    logic clk12mhz;

    IceboardTest_SDRAMReadWriteRandomly iceboardSDRAMTest(
        .clk12mhz(clk12mhz),
        .leds(leds),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_udqm(sdram_udqm),
        .sdram_ldqm(sdram_ldqm),
        .sdram_dq(sdram_dq)
    );

    mt48lc8m16a2 sdram(
        .Clk(sdram_clk),
        .Dq(sdram_dq),
        .Addr(sdram_a),
        .Ba(sdram_ba),
        .Cke(sdram_cke),
        .Cs_n(sdram_cs_),
        .Ras_n(sdram_ras_),
        .Cas_n(sdram_cas_),
        .We_n(sdram_we_),
        .Dqm({sdram_udqm, sdram_ldqm})
    );

//    mt48lc16m16a2 sdram(
//        .Clk(sdram_clk),
//        .Dq(sdram_dq),
//        .Addr({1'b0, sdram_a}),
//        .Ba(sdram_ba),
//        .Cke(sdram_cke),
//        .Cs_n(sdram_cs_),
//        .Ras_n(sdram_ras_),
//        .Cas_n(sdram_cas_),
//        .We_n(sdram_we_),
//        .Dqm({sdram_udqm, sdram_ldqm})
//    );

    initial begin
        $dumpfile("IceboardTest_SDRAMReadWriteRandomly.vcd");
        $dumpvars(0, IceboardTest_SDRAMReadWriteRandomlySim);

        #100000000;
//        #200000000;
//        #2300000000;
        $finish;
    end

    initial begin
        clk12mhz = 0;
        forever begin
            clk12mhz = !clk12mhz;
            #42;
        end
    end
endmodule

`endif
