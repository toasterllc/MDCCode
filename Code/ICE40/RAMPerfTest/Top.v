`include "Util.v"
`include "RAMController.v"
`include "Delay.v"

`ifdef SIM
`include "../../mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    
    input wire[1:0]     ram_cmd,
    input wire[2:0]     ram_cmd_block,
    output reg          ram_write_ready,
    input wire          ram_write_trigger,
    input wire[15:0]    ram_write_data,
    output reg          ram_write_done,
    output reg          ram_read_ready,
    input wire          ram_read_trigger,
    output wire[15:0]   ram_read_data,
    output reg          ram_read_done,
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    RAMController #(
        .ClkFreq(120_000_000),
        .BlockSize(2304*1296)
    ) RAMController(
        .clk(clk24mhz),
        
        .cmd(ram_cmd),
        .cmd_block(ram_cmd_block),
        
        .write_ready(ram_write_ready),
        .write_trigger(ram_write_trigger),
        .write_data(ram_write_data),
        .write_done(ram_write_done),
        
        .read_ready(ram_read_ready),
        .read_trigger(ram_read_trigger),
        .read_data(ram_read_data),
        .read_done(ram_read_done),
        
        .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq)
    );
endmodule

