`timescale 1ns/1ps

typedef bit[7:0] MyByte;

module Top(
    input wire clk24mhz,
    output wire[3:0] led
);
    wire clk = clk24mhz;
endmodule
