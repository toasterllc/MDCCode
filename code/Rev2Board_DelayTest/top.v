`include "../Util.v"
`include "../ClockGen.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps

module Inv(
    input wire in,
    output wire out
);
    assign out = !in;
endmodule

module Delay #(
    parameter Count = 1
)(
    input wire in,
    output wire out
);
    wire[Count:0] bits;
    assign bits[0] = in;
    assign out = bits[Count];
    
    genvar i;
    for (i=0; i<Count; i=i+1) begin
        (* keep *) (* syn_keep *) (* blackbox *) Inv Inv(.in(bits[i]), .out(bits[i+1]));
    end
endmodule

module Top(
    input wire          clk12mhz,
    output wire         sd_clk,
    output wire         sd_clk_delayed
);
    ClockGen #(
        .FREQ(96_000_000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen(.clk12mhz(clk12mhz), .clk(sd_clk));
    
    Delay #(
        .Count(100)
    ) Delay (
        .in(sd_clk),
        .out(sd_clk_delayed)
    );
    
endmodule

`ifdef SIM
module Testbench();
    reg         clk12mhz;
    wire        sd_clk;
    wire        sd_clk_delayed;
    
    Top Top(.*);
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        #100000000;
        `Finish;
    end
    
    initial begin
        forever begin
            clk12mhz = 0;
            #42;
            clk12mhz = 1;
            #42;
        end
    end
endmodule
`endif
