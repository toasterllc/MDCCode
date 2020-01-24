`define SYNTH
`timescale 1ns/1ps
`include "../SDRAMController.v"

module Random9(
    input logic clk, rst,
    output logic[8:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=9: x^9 + x^5 + 1
        else q <= {q[7:0], q[9-1] ^ q[5-1]};
endmodule

module Random16(
    input logic clk, rst,
    output logic[15:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=16: x^16 + x^15 + x^13 + x^4 + 1
        else q <= {q[14:0], q[16-1] ^ q[15-1] ^ q[13-1] ^ q[4-1]};
endmodule

module Random23(
    input logic clk, rst,
    output logic[22:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=23: x^23 + x^18 + 1
        else q <= {q[21:0], q[23-1] ^ q[18-1]};
endmodule

function [15:0] DataFromAddress;
    input [22:0] addr;
    DataFromAddress = {9'h1B5, addr[22:16]} ^ ~(addr[15:0]);
//    DataFromAddress = addr[15:0];
endfunction

module IceboardTest_SimpleReadWrite2(
    input logic         clk12mhz,
    
    output logic        ledFailed,
    output logic        ledDebug,
    
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
    
    localparam ClockFrequency = 12000000;       // 12 MHz
    assign clk = clk12mhz;
//    
//    localparam ClockFrequency =  6000000;     // 6 MHz
//    assign clk = clkDivider[0];
//
//    localparam ClockFrequency =  3000000;     // 3 MHz
//    assign clk = clkDivider[1];
//
//    localparam ClockFrequency =  1500000;     // 1.5 MHz
//    assign clk = clkDivider[2];
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
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    
    logic                   cmdReady;
    logic                   cmdTrigger;
    logic[AddrWidth-1:0]    cmdAddr;
    logic                   cmdWrite;
    logic[DataWidth-1:0]    cmdWriteData;
    logic[DataWidth-1:0]    cmdReadData;
    logic                   cmdReadDataValid;
    
    localparam MaxEnqueuedReads = 10;
    logic[(DataWidth*MaxEnqueuedReads)-1:0] expectedReadData;
    logic[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount;
    
    logic[DataWidth-1:0] currentExpectedReadData;
    assign currentExpectedReadData = expectedReadData[DataWidth-1:0];
    
    logic needInit;
    logic status;
    
    assign ledFailed = (status!=StatusOK);
    
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
    Random9 random9Gen(.clk(clk), .rst(rst), .q(random9));
    
    logic[15:0] random16;
    Random16 random16Gen(.clk(clk), .rst(rst), .q(random16));
    
    logic[22:0] random23;
    Random23 random23Gen(.clk(clk), .rst(rst), .q(random23));
    
    logic[22:0] randomAddr;
    assign randomAddr = random23%AddrCountLimit;
    
    task Read(input logic[22:0] addr);
        cmdTrigger <= 1;
        cmdAddr <= addr;
        cmdWrite <= 0;
        
        if (enqueuedReadCount >= MaxEnqueuedReads) begin
            `ifndef SYNTH
                $error("Too many enqueued reads");
            `endif
            
            status <= StatusFailed;
        end
        
        expectedReadData <= expectedReadData|(DataFromAddress(addr)<<(DataWidth*enqueuedReadCount));
        enqueuedReadCount <= enqueuedReadCount+1;
    endtask
    
    always @(posedge clk) begin
        // Set our default state if the current command was accepted
        if (cmdReady) cmdTrigger <= 0;
        
        if (rst) begin
            needInit <= 1;
            status <= StatusOK;
            
            cmdTrigger <= 0;
            cmdAddr <= 0;
            cmdWrite <= 0;
            cmdWriteData <= 0;
            
            expectedReadData <= 0;
            enqueuedReadCount <= 0;
            
            ledDebug <= 0;
        
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
                    needInit <= 0;
                    
                    // Kick off reading
                    Read(0);
                end
                
                $display("Write: %h", cmdAddr);
            end
        
        end else if (status == StatusOK) begin
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    // Verify that the data read out is what we expect
                    if (cmdReadData !== currentExpectedReadData) begin
                        `ifndef SYNTH
                            $error("Read invalid data (wanted: 0x%h/0x%h, got: 0x%h)", currentExpectedReadData, ~currentExpectedReadData, cmdReadData);
                        `endif
                        
                        status <= StatusFailed;
                    end
                    
                    expectedReadData <= expectedReadData >> DataWidth;
                    enqueuedReadCount <= enqueuedReadCount-1;
                
                // Something's wrong if we weren't expecting data and we got some
                end else begin
                    `ifndef SYNTH
                        $error("Received data when we didn't expect any");
                    `endif
                    
                    status <= StatusFailed;
                end
            end
            
            // Current command was accepted: prepare a new command
            else if (cmdReady) begin
                // A command was accepted, issue a new one
                $display("Read: %h", cmdAddr);
                
                Read((cmdAddr+1)&(AddrCountLimit-1));
                
                if (cmdAddr === 0) begin
                    ledDebug <= !ledDebug;
                end
            end
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"
`include "4012mt48lc16m16a2/mt48lc16m16a2.v"

module IceboardTest_SimpleReadWrite2Sim(
    output logic        ledFailed,
    output logic        ledDebug,

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

    IceboardTest_SimpleReadWrite2 iceboardSDRAMTest(
        .clk12mhz(clk12mhz),
        .ledFailed(ledFailed),
        .ledDebug(ledDebug),
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
        $dumpfile("IceboardTest_SimpleReadWrite2.vcd");
        $dumpvars(0, IceboardTest_SimpleReadWrite2Sim);

        #10000000;
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
