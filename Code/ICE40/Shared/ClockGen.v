`ifndef ClockGen_v
`define ClockGen_v

`include "Util.v"

`timescale 1ps/1ps

module ClockGen #(
    // 100MHz by default
    parameter FREQOUT=100000000,
    parameter DIVR=0,
    parameter DIVF=66,
    parameter DIVQ=3,
    parameter FILTER_RANGE=1
)(
    input wire clkRef,
    output wire clk,
    output wire rst
);
    wire locked;
    wire pllClk;
    assign clk = pllClk&locked;
    
    SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(DIVR),
        .DIVF(DIVF),
        .DIVQ(DIVQ),
        .FILTER_RANGE(FILTER_RANGE),
        .SIMFREQOUT(FREQOUT)
    ) pll (
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .REFERENCECLK(clkRef),
        .PLLOUTCORE(pllClk)
    );
    
    // Generate `rst`
    reg init = 0;
    reg[15:0] rst_;
    assign rst = !rst_[$size(rst_)-1];
    always @(posedge clk)
        if (!init) begin
            rst_ <= 1;
            init <= 1;
        end else if (rst) begin
            rst_ <= rst_<<1;
        end
    
    // TODO: should we only output clk if locked==1? that way, if clients receive a clock, they know it's stable?
    
    // // Generate `rst`
    // reg[15:0] rstCounter;
    // always @(posedge clk)
    //     if (!locked) rstCounter <= 0;
    //     else if (rst) rstCounter <= rstCounter+1;
    // assign rst = !(&rstCounter);
endmodule

`endif
