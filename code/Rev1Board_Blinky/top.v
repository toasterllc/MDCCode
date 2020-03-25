`timescale 1ns/1ps

module Top(
    output wire[7:0]    led
);
    assign led[7:0] = 8'b11110000;
endmodule
