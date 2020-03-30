`timescale 1ns/1ps
`include "../ClockGen.v"
`include "Iceboard_ImageProducer.v"

module Top(
    input wire clk12mhz,
    output wire wclk,
    output wire w,
    output wire[11:0] wd,
    output wire ledRed
);
    // 16 MHz clock
    wire clk;
    ClockGen #(
        .FREQ(16000000),
		.DIVR(0),
		.DIVF(84),
		.DIVQ(6),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst());
    
    Iceboard_ImageProducer producer(.clk(clk), .wclk(wclk), .w(w), .wd(wd), .ledRed(ledRed));
endmodule
