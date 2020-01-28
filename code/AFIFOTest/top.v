`timescale 1ns/1ps
`include "../AFIFO.v"

`define stringify(x) `"x```"

`ifdef SIM
`define assert(cond) if (!(cond)) $error("Assertion failed: %s (%s:%0d)", `stringify(cond), `__FILE__, `__LINE__)
`else
`define assert(cond)
`endif




`ifndef SIM







// /**
//  * PLL configuration
//  *
//  * This Verilog module was generated automatically
//  * using the icepll tool from the IceStorm project.
//  * Use at your own risk.
//  *
//  * Given input frequency:        12.000 MHz
//  * Requested output frequency:   80.000 MHz
//  * Achieved output frequency:    79.500 MHz
//  */
//
// module RCLKPLL(
//     input  clock_in,
//     output clock_out,
//     output locked
//     );
//
// SB_PLL40_CORE #(
//         .FEEDBACK_PATH("SIMPLE"),
//         .DIVR(4'b0000),        // DIVR =  0
//         .DIVF(7'b0110100),    // DIVF = 52
//         .DIVQ(3'b011),        // DIVQ =  3
//         .FILTER_RANGE(3'b001)    // FILTER_RANGE = 1
//     ) uut (
//         .LOCK(locked),
//         .RESETB(1'b1),
//         .BYPASS(1'b0),
//         .REFERENCECLK(clock_in),
//         .PLLOUTCORE(clock_out)
//         );
//
// endmodule






// /**
//  * PLL configuration
//  *
//  * This Verilog module was generated automatically
//  * using the icepll tool from the IceStorm project.
//  * Use at your own risk.
//  *
//  * Given input frequency:        12.000 MHz
//  * Requested output frequency:   78.500 MHz
//  * Achieved output frequency:    78.000 MHz
//  */
//
// module RCLKPLL(
//     input  clock_in,
//     output clock_out,
//     output locked
//     );
//
// SB_PLL40_CORE #(
//         .FEEDBACK_PATH("SIMPLE"),
//         .DIVR(4'b0000),        // DIVR =  0
//         .DIVF(7'b0110011),    // DIVF = 51
//         .DIVQ(3'b011),        // DIVQ =  3
//         .FILTER_RANGE(3'b001)    // FILTER_RANGE = 1
//     ) uut (
//         .LOCK(locked),
//         .RESETB(1'b1),
//         .BYPASS(1'b0),
//         .REFERENCECLK(clock_in),
//         .PLLOUTCORE(clock_out)
//         );
//
// endmodule


/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   81.000 MHz
 * Achieved output frequency:    81.000 MHz
 */

module RCLKPLL(
    input  clock_in,
    output clock_out,
    output locked
    );

SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),        // DIVR =  0
        .DIVF(7'b0110101),    // DIVF = 53
        .DIVQ(3'b011),        // DIVQ =  3
        .FILTER_RANGE(3'b001)    // FILTER_RANGE = 1
    ) uut (
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .REFERENCECLK(clock_in),
        .PLLOUTCORE(clock_out)
        );

endmodule





/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   80.000 MHz
 * Achieved output frequency:    79.500 MHz
 */

module WCLKPLL(
	input  clock_in,
	output clock_out,
	output locked
	);

SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(4'b0000),		// DIVR =  0
		.DIVF(7'b0110100),	// DIVF = 52
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

`endif


module AFIFOTest(
    input wire clk12mhz,
    output wire led
);

`ifdef SIM
    initial begin
        // $dumpfile("top.vcd");
        // $dumpvars(0, AFIFOTest);
        #1000000000;
        $finish;
    end
    
    // rclk
    reg rclk = 0;
    initial begin
        #7;
        forever begin
            rclk = !rclk;
            #30;
        end
    end
    
    // wclk
    reg wclk = 0;
    initial begin
        forever begin
            wclk = !wclk;
            #42;
        end
    end
`else
    wire rclk;
    RCLKPLL pll1(.clock_in(clk12mhz), .clock_out(rclk));
    
    wire wclk;
    WCLKPLL pll2(.clock_in(clk12mhz), .clock_out(wclk));
`endif
    
    // wire wclk;
    // assign wclk = rclk;
    
    reg r = 0;
    wire[11:0] rd;
    wire rok;
    
    reg w = 0;
    reg[11:0] wd;
    wire wok;
    
    AFIFO afifo(
        .rclk(rclk),
        .r(r),
        .rd(rd),
        .rok(rok),
        .wclk(wclk),
        .w(w),
        .wd(wd),
        .wok(wok)
    );
    
    // Produce values
    always @(posedge wclk) begin
        // Init
        if (!w) begin
            w <= 1;
            wd <= 0;
        end else begin
            // We wrote a value, continue to the next one
            wd <= wd+1'b1;
            if (wok) $display("Wrote value: %h", wd);
            else $display("Error: failed to write value: %h", wd);
        end
    end
    
    // Consume values
    reg[11:0] rval;
    reg rvalValid = 0;
    reg rfail = 0;
    always @(posedge rclk) begin
        if (!rfail) begin
            // Init
            if (!r) begin
                r <= 1;
            
            // Read if data is available
            end else if (rok) begin
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
endmodule
