`define SYNTH
`include "SDRAMController.v"

module Top(
    input logic clk,
    input logic rst,

    output logic sdram_clk,
    output logic sdram_cke,
    output logic[1:0] sdram_ba,
    output logic[11:0] sdram_a,
    output logic sdram_cs_,
    output logic sdram_ras_,
    output logic sdram_cas_,
    output logic sdram_we_,
    output logic sdram_ldqm,
    output logic sdram_udqm,
    inout logic[15:0] sdram_dq
);

    logic cmdReady;
    logic cmdTrigger;
    logic[22:0] cmdAddr;
    logic cmdWrite;
    logic[15:0] cmdWriteData;
    logic[15:0] cmdReadData;
    logic cmdReadDataValid;
    
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
endmodule
