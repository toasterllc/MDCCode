`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../SDRAMController.v"

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

module Top(
    input wire          clk12mhz,
    
    output wire[7:0]    led,
    
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
    function [15:0] DataFromAddr;
        input [24:0] addr;
        DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
        // DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
    endfunction
    
    // 100 MHz clock
    localparam ClockFrequency = 100000000;
    wire clk;
    wire rst;
    ClockGen #(
        .FREQ(ClockFrequency),
		.DIVR(0),
		.DIVF(66),
		.DIVQ(3),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst(rst));
    
    localparam AddrWidth = 25;
    localparam DataWidth = 16;
    
    wire                  cmdReady;
    reg                   cmdTrigger = 0;
    reg[AddrWidth-1:0]    cmdAddr = 0;
    reg                   cmdWrite = 0;
    reg[DataWidth-1:0]    cmdWriteData = 0;
    wire[DataWidth-1:0]   cmdReadData;
    wire                  cmdReadDataValid;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
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
    
    always @(posedge clk) begin
        if (cmdReady) begin
            // // Continuous reads
            // cmdTrigger <= 1;
            // cmdAddr <= cmdAddr+1;
            // cmdWrite <= 0;
            
            
            // // Continuous writes
            // cmdTrigger <= 1;
            // cmdAddr <= cmdAddr+1;
            // cmdWrite <= 1;
            // cmdWriteData <= DataFromAddr(cmdAddr+1);
        end
    end
    
`ifdef SIM
    mobile_sdr sdram(
        .clk(ram_clk),
        .cke(ram_cke),
        .addr(ram_a),
        .ba(ram_ba),
        .cs_n(ram_cs_),
        .ras_n(ram_ras_),
        .cas_n(ram_cas_),
        .we_n(ram_we_),
        .dq(ram_dq),
        .dqm(ram_dqm)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
        #1000000000;
        $finish;
    end
`endif
endmodule
