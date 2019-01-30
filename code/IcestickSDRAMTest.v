// `define SYNTH
`timescale 1ns/1ps
`include "SDRAMController.v"

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
    
    `define dataFromAddress(addr) ~addr
    
    logic status;
    logic[7:0] readAddr;
    
    assign cmdTrigger = (cmdReady && status==StatusOK);
    assign cmdWriteData = `dataFromAddress(cmdAddr);
    
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
    
    always @(posedge clk) begin
        if (rst) begin
            cmdWrite <= 1;
            cmdAddr <= 0;
            
            status <= StatusOK;
            readAddr <= 0;
        
        end else if (status == StatusOK) begin
            if (cmdReadDataValid) begin
                // Verify that the data read out is what we expect
                if (cmdReadData == `dataFromAddress(readAddr))
                    status <= StatusOK;
                else
                    status <= StatusFailed;
                
                readAddr <= readAddr+1;
            end
            
            // Update our state
            if (cmdReady) begin
                if (cmdAddr < 8'hFF) begin
                    cmdAddr <= cmdAddr+1;
                end else begin
                    cmdWrite <= !cmdWrite;
                    cmdAddr <= 0;
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
