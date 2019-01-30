// `define SYNTH
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

module IcestickSDRAMTest(
    input logic         clk,
    input logic         rst,
    
    output logic        ledRed,
    output logic        ledGreen,
    
    output logic        sdram_clk,
    output logic        sdram_cke,
    // Use the high bits of `sdram_a` because we need A[10] for precharging to work!
    output logic[11:4]  sdram_a,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_dqm,
    inout logic[7:0]    sdram_dq
);
    
    logic               cmdReady;
    logic               cmdTrigger;
    logic[20:13]        cmdAddr;
    logic               cmdWrite;
    logic[7:0]          cmdWriteData;
    logic[7:0]          cmdReadData;
    logic               cmdReadDataValid;
    
    logic[1:0]          sdram_ba;
    
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    
    `define dataFromAddress(addr) ~(addr)
    
    logic needInit;
    logic status;
    logic[23:0] enqueuedReadAddr;
    logic[2:0] enqueuedReadCount;
    
    // assign cmdTrigger = (cmdReady && status==StatusOK);
    // assign cmdWriteData = `dataFromAddress(cmdAddr);
    
    assign ledRed = (status==StatusFailed);
    assign ledGreen = (status==StatusOK);
    
    logic[3:0] ignored_sdram_a;
    logic[7:0] ignored_cmdReadData;
    logic[7:0] ignored_sdram_dq;
    
    SDRAMController sdramController(
        .clk(clk),
        .rst(rst),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr({2'b0, cmdAddr, 13'b0}),
        .cmdWrite(cmdWrite),
        .cmdWriteData({8'b0, cmdWriteData}),
        .cmdReadData({ignored_cmdReadData, cmdReadData}),
        .cmdReadDataValid(cmdReadDataValid),
        
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a({sdram_a, ignored_sdram_a}),
        .sdram_cs_(),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_ldqm(sdram_dqm),
        .sdram_udqm(),
        .sdram_dq({ignored_sdram_dq, sdram_dq})
    );
    
    logic[7:0] randomBits;
    RandomNumberGenerator #(.SEED(1)) rng(.clk(clk), .rst(rst), .q(randomBits));
    
    logic[7:0] randomAddr;
    RandomNumberGenerator #(.SEED(42)) rng2(.clk(clk), .rst(rst), .q(randomAddr));
    
    logic shouldWrite;
    assign shouldWrite = randomBits[0] || enqueuedReadCount>=3;
    
    always @(posedge clk) begin
        if (rst) begin
            cmdTrigger <= 0;
            needInit <= 1;
            status <= StatusOK;
            enqueuedReadAddr <= 0;
            enqueuedReadCount <= 0;
        
        // Initialize memory to known values
        end else if (needInit) begin
            if (!cmdTrigger) begin
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= `dataFromAddress(0);
                cmdTrigger <= 1;
            end else if (cmdReady) begin
                // if (cmdAddr == 8'h63) begin
                //     cmdAddr <= cmdAddr+1;
                //     cmdWriteData <= `dataFromAddress(cmdAddr);
                // end else
                if (cmdAddr < 8'hFF) begin
                    cmdAddr <= cmdAddr+1;
                    cmdWriteData <= `dataFromAddress(cmdAddr+1);
                end else begin
                    // Next stage
                    needInit <= 0;
                    cmdTrigger <= 0;
                end
            end
        
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
                    if (cmdReadData == `dataFromAddress(enqueuedReadAddr[7:0]))
                        status <= StatusOK;
                    else
                        status <= StatusFailed;
                    
                    enqueuedReadAddr <= enqueuedReadAddr>>8;
                
                // Something's wrong if we weren't expecting data and we got some
                end else status <= StatusFailed;
            
            // Otherwise issue a new command
            end else if (!cmdTrigger || (cmdTrigger && cmdReady)) begin
                // Prepare a command
                cmdWrite <= shouldWrite;
                cmdAddr <= randomAddr;
                cmdTrigger <= 1;
                
                // If we're writing, load the data into cmdWriteData
                if (shouldWrite) cmdWriteData <= `dataFromAddress(randomAddr);
                // If we're reading, remember the address that we're expecting data from
                else begin
                    enqueuedReadAddr <= enqueuedReadAddr|(randomAddr<<(8*enqueuedReadCount));
                    enqueuedReadCount <= enqueuedReadCount+1;
                end
            end
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

module IcestickSDRAMTestSim(
    output logic        ledRed,
    output logic        ledGreen,
    
    output logic        sdram_clk,
    output logic        sdram_cke,
    // Use the high bits of `sdram_a` because we need A[10] for precharging to work!
    output logic[11:4]  sdram_a,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_dqm,
    inout logic[7:0]    sdram_dq
);
    
    logic clk;
    logic rst;
    
    IcestickSDRAMTest icestickSDRAMTest(
        .clk(clk),
        .rst(rst),
        .ledRed(ledRed),
        .ledGreen(ledGreen),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_a(sdram_a),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq)
    );
    
    logic[7:0] ignored_Dq;
    mt48lc8m16a2 sdram(
        .Clk(sdram_clk),
        .Dq({ignored_Dq, sdram_dq}),
        .Addr({sdram_a, 4'b0}),
        .Ba(2'b0),
        .Cke(sdram_cke),
        .Cs_n(1'b0),
        .Ras_n(sdram_ras_),
        .Cas_n(sdram_cas_),
        .We_n(sdram_we_),
        .Dqm({sdram_dqm, sdram_dqm})
    );
    
    initial begin
        $dumpfile("IcestickSDRAMTest.vcd");
        $dumpvars(0, IcestickSDRAMTestSim);
        
        // Reset
        rst = 1;
        #100;
        rst = 0;
        
        #1000000;
        $finish;
    end
    
    initial begin
        clk = 0;
        forever begin
            clk = !clk;
            #83;
        end
    end
endmodule

`endif
