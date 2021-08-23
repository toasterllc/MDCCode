`include "ClockGen.v"
`include "Util.v"
`timescale 1ns/1ps

module Top(
    input wire ice_img_clk16mhz,
    output wire[3:0] ice_led
);
    wire clk16mhz = ice_img_clk16mhz;
    
    wire clk;
    ClockGen #(
        .FREQOUT(32000000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(5),
        .FILTER_RANGE(1)
    ) ClockGen(.clkRef(clk16mhz), .clk(clk));
    
`ifdef SIM
    reg[7:0] counter = 0;
`else
    // .95 Hz (assuming 32 MHz clock)
    reg[26:0] counter = 0;
`endif
    always @(posedge clk) begin
        counter <= counter+1;
    end
    
    wire slowClk = `LeftBit(counter, 0);
    reg outEn = 0;
    reg ledOtherVal = 0;
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_test (
        .INPUT_CLK(slowClk),
        .OUTPUT_CLK(slowClk),
        .PACKAGE_PIN(ice_led[0]),
        .OUTPUT_ENABLE(outEn),
        .D_OUT_0(1'b1)
    );
    
    always @(posedge slowClk) begin
        outEn <= !outEn;
        ledOtherVal <= 1;
    end
    
    assign ice_led[3:1] = {3{ledOtherVal}};
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
