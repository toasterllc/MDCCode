//`define SYNTH
`timescale 1ns/1ps
`include "SDRAMController.v"

module RandomNumberGenerator(
    input logic clk,
    input logic rst,
    output logic[7:0] q
);
    parameter SEED = 8'd1;
    always @(posedge clk)
    if (rst) q <= SEED; // anything except zero
     // polynomial for maximal LFSR
    else q <= {q[6:0], q[7] ^ q[5] ^ q[4] ^ q[3]};
endmodule

module Scrambler(
    input logic[22:0] d,
    output logic[22:0] q
);
    assign q[00] = d[00];
    assign q[01] = d[01];
    assign q[02] = d[02];
    assign q[03] = d[03];
    assign q[04] = d[04];
    assign q[05] = d[05];
    assign q[06] = d[06];
    assign q[07] = d[07];
    assign q[08] = d[08];
    assign q[09] = d[09];
    assign q[10] = d[10];
    assign q[11] = d[11];
    assign q[12] = d[12];
    assign q[13] = d[13];
    assign q[14] = d[14];
    assign q[15] = d[15];
    assign q[16] = d[16];
    assign q[17] = d[17];
    assign q[18] = d[18];
    assign q[19] = d[19];
    assign q[20] = d[20];
    assign q[21] = d[21];
    assign q[22] = d[22];
    
//    assign q[00] = d[15];
//    assign q[01] = d[21];
//    assign q[02] = d[20];
//    assign q[03] = d[10];
//    assign q[04] = d[02];
//    assign q[05] = d[22];
//    assign q[06] = d[13];
//    assign q[07] = d[06];
//    assign q[08] = d[16];
//    assign q[09] = d[11];
//    assign q[10] = d[17];
//    assign q[11] = d[12];
//    assign q[12] = d[07];
//    assign q[13] = d[08];
//    assign q[14] = d[01];
//    assign q[15] = d[09];
//    assign q[16] = d[18];
//    assign q[17] = d[05];
//    assign q[18] = d[03];
//    assign q[19] = d[00];
//    assign q[20] = d[04];
//    assign q[21] = d[14];
//    assign q[22] = d[19];
endmodule

module IceboardTest_SDRAMReadWriteRandomly(
    input logic         clk12mhz,

    output logic        ledRed,
    output logic        ledGreen,

    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_ldqm,
    output logic        sdram_udqm,
    inout logic[15:0]   sdram_dq
);
    localparam ClockFrequency = 12000000;
    
    `define RESET_BIT 26

    logic[`RESET_BIT:0] clkDivider;

    `ifndef SYNTH
    initial clkDivider = 0;
    `endif
    
    always @(posedge clk12mhz) clkDivider <= clkDivider+1;
    
    logic clk;
    assign clk = clk12mhz;
    
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
        
        // // Generate a reset every time clkDivider[`RESET_BIT] goes 0->1
        // lastBit <= clkDivider[`RESET_BIT];
        // if (clkDivider[`RESET_BIT] && !lastBit) begin
        //     rstCounter <= 0;
        // end
    end
    assign ledGreen = rst;
    
    `ifndef SYNTH
    initial rstCounter = 0;
    `endif
    
    localparam AddrWidth = 23;
    localparam MaxEnqueuedReads = 3;
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    
    `define dataFromAddress(addr) (addr[15:0])
//    `define dataFromAddress(addr) ({9'h1B5, addr[22:16]} ^ ~(addr[15:0]))
//    `define dataFromAddress(addr) 23'd0
    
    logic                   cmdReady;
    logic                   cmdTrigger;
    logic[AddrWidth-1:0]    cmdAddr;
    logic                   cmdWrite;
    logic[15:0]             cmdWriteData;
    logic[15:0]             cmdReadData;
    logic                   cmdReadDataValid;
    
    logic needInit;
    logic status;
    logic[(AddrWidth*MaxEnqueuedReads)-1:0] enqueuedReadAddr;
    logic[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount;
    
    assign ledRed = (status!=StatusOK);
    
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
        .sdram_ldqm(sdram_ldqm),
        .sdram_udqm(sdram_udqm),
        .sdram_dq(sdram_dq)
    );
    
    logic[7:0] randomBits;
    RandomNumberGenerator #(.SEED(22)) rng(.clk(clk), .rst(rst), .q(randomBits));
    logic shouldWrite;
    assign shouldWrite = randomBits[0] || enqueuedReadCount>=MaxEnqueuedReads;
    
    logic[AddrWidth-1:0] readCounter;
    logic[AddrWidth-1:0] scrambledReadAddr;
    Scrambler readAddrScrambler(.d(readCounter), .q(scrambledReadAddr));
    
    logic[AddrWidth-1:0] writeCounter;
    logic[AddrWidth-1:0] scrambledWriteAddr;
    Scrambler writeAddrScrambler(.d(writeCounter), .q(scrambledWriteAddr));
    
    logic[AddrWidth-1:0] currentReadAddress;
    assign currentReadAddress = enqueuedReadAddr[AddrWidth-1:0];
    
    always @(posedge clk) begin
        if (rst) begin
            cmdTrigger <= 0;
            needInit <= 1;
            status <= StatusOK;
            enqueuedReadAddr <= 0;
            enqueuedReadCount <= 0;
            readCounter <= 0;
            writeCounter <= 0;
        
        // Initialize memory to known values
        end else if (needInit) begin
            if (!cmdTrigger) begin
                cmdAddr <= scrambledWriteAddr;
                cmdWriteData <= `dataFromAddress(scrambledWriteAddr);
                writeCounter <= writeCounter+1;
                
                cmdWrite <= 1;
                cmdTrigger <= 1;
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
//                if (writeCounter < 'h100) begin
                
                cmdAddr <= scrambledWriteAddr;
                cmdWriteData <= `dataFromAddress(scrambledWriteAddr);
                
//                    if (scrambledWriteAddr == 0) begin
//                        cmdWriteData <= `dataFromAddress(scrambledWriteAddr);
//                    end else begin
//                        cmdWriteData <= 16'h1234;
//                    end
                
                
//                if (writeCounter < 'h7FFFFF) begin
                if (writeCounter < 'hFF) begin
                    writeCounter <= writeCounter+1;
                
                end else begin
                    // Next stage
                    
                    
                    readCounter <= 'hFE; // Start at a random address
                    writeCounter <= 0; // Start at a random address
                    
//                    readCounter <= 'h04C505; // Start at a random address
//                    writeCounter <= 'h68A052; // Start at a random address
                    needInit <= 0;
                end
            end
        
        //end else begin
        end else if (status == StatusOK) begin
            // Prevent duplicate commands
            if (cmdTrigger && cmdReady) begin
                cmdTrigger <= 0;
            end
            
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    enqueuedReadCount <= enqueuedReadCount-1;
                    
                    // Verify that the data read out is what we expect
                    if (cmdReadData == `dataFromAddress(currentReadAddress)) begin
                        status <= StatusOK;
                    end else begin
                        status <= StatusFailed;
                    end
                    
                    enqueuedReadAddr <= enqueuedReadAddr >> AddrWidth;
                
                // Something's wrong if we weren't expecting data and we got some
                end else status <= StatusFailed;
            
            // Otherwise issue a new command
            end else if (!cmdTrigger || (cmdTrigger && cmdReady)) begin
                // Prepare a command
                cmdWrite <= shouldWrite;
                
                if (shouldWrite) begin
                    cmdAddr <= scrambledWriteAddr;
                    writeCounter <= writeCounter-1;
                end else begin
                    cmdAddr <= scrambledReadAddr;
                    readCounter <= readCounter+1;
                end
                
                cmdTrigger <= 1;
                
                
                // If we're writing, load the data into cmdWriteData
                if (shouldWrite) begin
                    if (scrambledWriteAddr != 0) begin
                        cmdWriteData <= `dataFromAddress(scrambledWriteAddr);
                    end else begin
                        cmdWriteData <= 16'h1234;
                    end
                end
                
//                // If we're writing, load the data into cmdWriteData
//                if (shouldWrite) cmdWriteData <= `dataFromAddress(scrambledWriteAddr);
                // If we're reading, remember the address that we're expecting data from
                else begin
                    enqueuedReadAddr <= enqueuedReadAddr|(scrambledReadAddr<<(AddrWidth*enqueuedReadCount));
                    enqueuedReadCount <= enqueuedReadCount+1;
                end
            end
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

module IceboardTest_SDRAMReadWriteRandomlySim(
    output logic        ledRed,
    output logic        ledGreen,

    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_ldqm,
    output logic        sdram_udqm,
    inout logic[15:0]   sdram_dq
);

    logic clk12mhz;

    IceboardTest_SDRAMReadWriteRandomly iceboardSDRAMTest(
        .clk12mhz(clk12mhz),
        .ledRed(ledRed),
        .ledGreen(ledGreen),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_ldqm(sdram_ldqm),
        .sdram_udqm(sdram_udqm),
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

    initial begin
        $dumpfile("IceboardTest_SDRAMReadWriteRandomly.vcd");
        $dumpvars(0, IceboardTest_SDRAMReadWriteRandomlySim);

        #10000000;
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
