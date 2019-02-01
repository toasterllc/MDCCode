`define SYNTH
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
    input logic         clk12mhz,
    
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
    
    logic[7:0] clkdivider;
    `ifndef SYNTH
        always @(posedge rst) clkdivider <= 0;
    `endif
    
    always @(posedge clk12mhz)
        clkdivider <= clkdivider+1;
    
    logic clk;
    assign clk = clkdivider[0];
    
    logic[19:0] rstCounter;
    logic rst;
    assign rst = !rstCounter[$size(rstCounter)-1];
    
    always @(posedge clk) if (rst) rstCounter <= rstCounter+1;
    
    always @(posedge clk) begin
        if (rst) begin
            ledGreen <= 0;
            ledRed <= 1;
        end else begin
            ledGreen <= 1;
            ledRed <= 0;
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
        .clk12mhz(clk),
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
        rst = 0;
        #100;
        rst = 1;
        #100000;
        rst = 0;
        
        #100000000;
        $finish;
    end
    
    initial begin
        clk = 0;
        forever begin
            clk = !clk;
            #42;
        end
    end
endmodule

`endif
