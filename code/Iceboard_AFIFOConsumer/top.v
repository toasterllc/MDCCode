`timescale 1ns/1ps
`include "../AFIFO.v"

`ifdef SIM
`include "../Icestick_AFIFOProducer/top.v"
`endif



`ifndef SIM


/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   17.000 MHz
 * Achieved output frequency:    16.875 MHz
 */

module CLKPLL(
	input  clock_in,
	output clock_out,
	output locked
	);

SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(4'b0000),		// DIVR =  0
		.DIVF(7'b0101100),	// DIVF = 44
		.DIVQ(3'b101),		// DIVQ =  5
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

module Iceboard_AFIFOConsumer(
    input wire clk12mhz,
    output wire led,
    
    input wire wclk,
    input wire w,
    input wire[11:0] wd
);

`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Iceboard_AFIFOConsumer);
        #1000000000;
        $finish;
    end
    
    // clk
    reg clk = 0;
    initial begin
        #7;
        forever begin
            clk = !clk;
            #30;
        end
    end
    
    Icestick_AFIFOProducer producer(.clk12mhz(clk12mhz), .wclk(wclk), .w(w), .wd(wd));
`else
    wire clk;
    CLKPLL pll(.clock_in(clk12mhz), .clock_out(clk));
`endif
    
    // wire wclk;
    // assign wclk = clk;
    
    reg r = 0;
    wire[11:0] rd;
    wire rempty;
    
    AFIFO afifo(
        .rclk(clk),
        .r(r),
        .rd(rd),
        .rempty(rempty),
        
        .wclk(wclk),
        .w(w),
        .wd(wd),
        .wfull()
    );
    
// `ifdef SIM
//     reg[7:0] rstCounter = 0;
// `else
//     reg[24:0] rstCounter = 0; // 2 second reset
// `endif
//
//     wire rst = !(&rstCounter);
//     always @(posedge clk)
//         if (rst)
//             rstCounter <= rstCounter+1;
    
    // always @(posedge wclk) begin
    //     if (rst) led <= 0;
    //     else led <= 1;
    // end
    
    // Consume values
    reg[11:0] rval;
    reg rvalValid = 0;
    reg rfail = 0;
    always @(posedge clk) begin
        if (!rfail) begin
            // Init
            if (!r) begin
                r <= 1;
            
            // Read if data is available
            end else if (!rempty) begin
                $display("Read value: %h", rd);
                rval <= rd;
                rvalValid <= 1;
                
                // Check if the current value is the previous value +1
                // `assert(!rvalValid | ((rval+1'b1)==rd));
                if (rvalValid & ((rval+1'b1)!=rd)) begin
                    $display("Error: read invalid value; wanted: %h got: %h", (rval+1'b1), rd);
                    rfail <= 1;
                    // Stop reading
                    r <= 0;
                end
            end
        end
    end
    
    assign led = rfail;
    // assign led = !rempty;
    // assign led = rvalValid;
endmodule
