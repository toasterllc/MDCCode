`timescale 1ns/1ps

module Top(
    input wire          clk,
    
    output wire[9:0]    ANY_OUT,
    
    // input wire          B6,
    output wire         B6,
    
    // input wire          L5,
    output wire         L5,
);
    SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(0),
		.DIVF(68),
		.DIVQ(2),
		.FILTER_RANGE(1)
    ) a (
		.LOCK(),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		.REFERENCECLK(clk),
		.PLLOUTCORE(ANY_OUT[0])
    );
    
    SB_PLL40_CORE #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(0),
		.DIVF(63),
		.DIVQ(3),
		.FILTER_RANGE(1)
    ) b (
		.LOCK(),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		.REFERENCECLK(clk),
		.PLLOUTCORE(ANY_OUT[1])
    );
endmodule
