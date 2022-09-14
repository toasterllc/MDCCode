`include "ClockGen.v"
`include "Util.v"
`timescale 1ns/1ps

module Top(
    input wire ice_img_clk16mhz,
    output wire[7:0] ice_stm_spi_d,
    output wire[3:0] ice_led
);
    assign ice_stm_spi_d = 0;
    
    wire clk16mhz = ice_img_clk16mhz;
    
    wire clk;
    ClockGen #(
        .FREQOUT(32000000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(5),
        .FILTER_RANGE(1)
    ) ClockGen(.clkRef(clk16mhz), .clk(clk));
    
    // .95 Hz (assuming 32 MHz clock)
    reg[20:0] counter = 0;
    always @(posedge clk) begin
        counter <= counter+1;
    end
    
    assign ice_led[3:0] = {4{`LeftBit(counter, 0)}};
endmodule

`ifdef SIM
module Testbench();
    reg ice_img_clk16mhz = 0;
    wire[3:0] ice_led;
    Top Top(
        .ice_img_clk16mhz(ice_img_clk16mhz),
        .ice_led(ice_led)
    );
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
endmodule
`endif
