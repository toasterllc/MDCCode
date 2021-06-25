`include "ClockGen.v"
`timescale 1ns/1ps

module Top(
    input wire ice_img_clk16mhz,
    output wire[3:0] ice_led
);
    wire clk16mhz = ice_img_clk16mhz;
    wire clk;
    ClockGen #(
        .OUTFREQ(32000000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(5),
        .FILTER_RANGE(1)
    ) ClockGen(.clkRef(clk16mhz), .clk(clk));
    
    reg[20:0] counter = 0;
    always @(posedge clk) begin
        counter <= counter+1;
    end
    
    assign ice_led[3:0] = {4{counter[$size(counter)-1]}};
endmodule
