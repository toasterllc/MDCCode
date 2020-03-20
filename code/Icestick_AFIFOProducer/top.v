`timescale 1ns/1ps
`include "../ClockGen.v"

module Top(
    input wire clk12mhz,
    output wire wclk,
    output wire w,
    output wire[11:0] wd
);
    // 16 MHz clock
    wire clk;
    ClockGen #(
        .FREQ(16),
		.DIVR(0),
		.DIVF(84),
		.DIVQ(6),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst());
    
    Icestick_AFIFOProducer producer(.clk(clk), .wclk(wclk), .w(w), .wd(wd));
endmodule
