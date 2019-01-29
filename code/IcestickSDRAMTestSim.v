`define SYNTH
`include "SDRAMController.v"

module IcestickSDRAMTest(
    input logic clk,
    input logic rst,
    
    output logic sdram_clk,
    output logic sdram_cke,
    output logic[7:0] sdram_a,
    output logic sdram_ras_,
    output logic sdram_cas_,
    output logic sdram_we_,
    output logic sdram_dqm,
    inout logic[7:0] sdram_dq
);
    
    logic cmdReady;
    logic cmdTrigger;
    logic[22:0] cmdAddr;
    logic cmdWrite;
    logic[15:0] cmdWriteData;
    logic[15:0] cmdReadData;
    logic cmdReadDataValid;
    
    logic           internal_sdram_clk;
    logic           internal_sdram_cke;
    logic[1:0]      internal_sdram_ba;
    logic[11:0]     internal_sdram_a;
    logic           internal_sdram_cs_;
    logic           internal_sdram_ras_;
    logic           internal_sdram_cas_;
    logic           internal_sdram_we_;
    logic           internal_sdram_ldqm;
    logic           internal_sdram_udqm;
    logic[15:0]     internal_sdram_dq;
    
    assign sdram_clk    = internal_sdram_clk;
    assign sdram_cke    = internal_sdram_cke;
    assign sdram_a      = internal_sdram_a[7:0];
    assign sdram_ras_   = internal_sdram_ras_;
    assign sdram_cas_   = internal_sdram_cas_;
    assign sdram_we_    = internal_sdram_we_;
    assign sdram_dqm    = internal_sdram_ldqm;
    assign sdram_dq     = internal_sdram_dq[7:0];
    
    SDRAMController sdramController(
        .clk(clk),
        .rst(rst),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
        .sdram_clk(internal_sdram_clk),
        .sdram_cke(internal_sdram_cke),
        .sdram_ba(internal_sdram_ba),
        .sdram_a(internal_sdram_a),
        .sdram_cs_(internal_sdram_cs_),
        .sdram_ras_(internal_sdram_ras_),
        .sdram_cas_(internal_sdram_cas_),
        .sdram_we_(internal_sdram_we_),
        .sdram_ldqm(internal_sdram_ldqm),
        .sdram_udqm(internal_sdram_udqm),
        .sdram_dq(internal_sdram_dq)
    );
endmodule
