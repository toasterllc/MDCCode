`timescale 1ns/1ps
`include "../SDRAMController.v"

module ClockGenerator(
    input  clock_in,
    output clock_out,
    output locked
);
    SB_PLL40_CORE #(
    		.FEEDBACK_PATH("SIMPLE"),
    		.DIVR(4'b0000),		// DIVR =  0
    		.DIVF(7'b1000010),	// DIVF = 66
    		.DIVQ(3'b011),		// DIVQ =  3
    		.FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
    	) uut (
    		.LOCK(locked),
    		.RESETB(1'b1),
    		.BYPASS(1'b0),
    		.REFERENCECLK(clock_in),
    		.PLLOUTCORE(clock_out)
    		);
endmodule

module Iceboard_SimpleWriteTest(
    input wire          clk12mhz,   // 12 MHz crystal
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[11:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire         ram_udqm,
    output wire         ram_ldqm,
    inout wire[15:0]    ram_dq
);
    localparam ClockFrequency = 100000000; // 100 MHz
    
    localparam RAM_AddrWidth = 23;
    localparam RAM_DataWidth = 16;
    
    wire clk;
    ClockGenerator clockGen(
        .clock_in(clk12mhz),
        .clock_out(clk),
        .locked()
    );
    
    // RAM
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    wire[RAM_DataWidth-1:0] ram_cmdWriteData;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        .rst(0), // TODO: figure out resetting
        
        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(),
        .cmdReadDataValid(),
        
        .sdram_clk(ram_clk),
        .sdram_cke(ram_cke),
        .sdram_ba(ram_ba),
        .sdram_a(ram_a),
        .sdram_cs_(ram_cs_),
        .sdram_ras_(ram_ras_),
        .sdram_cas_(ram_cas_),
        .sdram_we_(ram_we_),
        .sdram_udqm(ram_udqm),
        .sdram_ldqm(ram_ldqm),
        .sdram_dq(ram_dq)
    );
    
    assign ram_cmdWriteData = 0;
    
    always @(posedge clk) begin
        if (!ram_cmdTrigger) begin
            ram_cmdTrigger <= 1;
            ram_cmdWrite <= 1;
        
        end else if (ram_cmdReady) begin
            ram_cmdAddr <= ram_cmdAddr+1;
        end
    end
    
endmodule
