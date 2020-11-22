`include "CRC7.v"

`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    input wire rst,
    input wire en,
    input wire din,
    output wire dout
);
    CRC7 crc(
        .clk(clk24mhz),
        .rst(rst),
        .en(en),
        .din(din),
        .dout(dout)
    );
endmodule
