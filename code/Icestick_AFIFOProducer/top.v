`timescale 1ns/1ps

`ifndef SIM

/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   16.000 MHz
 * Achieved output frequency:    15.938 MHz
 */

module WCLKPLL(
	input  clock_in,
	output clock_out,
	output locked
	);

SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(4'b0000),		// DIVR =  0
		.DIVF(7'b1010100),	// DIVF = 84
		.DIVQ(3'b110),		// DIVQ =  6
		.FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
	) uut (
		.LOCK(locked),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		.REFERENCECLK(clock_in),
		.PLLOUTCORE(clock_out)
		);

endmodule

`endif

module Icestick_AFIFOProducer(
    input wire clk12mhz,
    
`ifdef SIM
    output reg wclk = 0,
`else
    output wire wclk,
`endif
    output reg w = 0,
    output reg[11:0] wd = 0
);

`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Icestick_AFIFOProducer);
        #10000000;
        $finish;
    end
    
    // wclk (16 MHz)
    initial begin
        forever begin
            wclk = !wclk;
            #31;
        end
    end
    
    reg[7:0] rstCounter = 0;
`else
    reg[25:0] rstCounter = 0; // 4 second reset
    WCLKPLL pll(.clock_in(clk12mhz), .clock_out(wclk));
`endif
    
    wire rst = !(&rstCounter);
    always @(posedge wclk)
        if (rst)
            rstCounter <= rstCounter+1;
    
    // Produce values
    always @(posedge wclk) begin
        if (!rst) begin
            if (w) begin
                // We wrote a value, continue to the next one
                $display("Wrote value: %h", wd);
            end
            
            w <= 1;
            wd <= wd+1'b1;
        end
    end
endmodule
