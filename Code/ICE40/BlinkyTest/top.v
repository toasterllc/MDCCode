`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output wire[3:0] led
);
    wire clk = clk24mhz;
    reg[3:0][7:0] myreg = 0;
endmodule
