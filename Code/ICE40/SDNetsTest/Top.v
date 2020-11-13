`include "ClockGen.v"

`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output wire[3:0] led,
    output wire sd_init,
    output wire sd_clk,
    output wire sd_cmd,
    output wire[3:0] sd_dat,
);
    // ====================
    // Fast Clock (207 MHz)
    // ====================
    localparam FastClkFreq = 207_000_000;
    wire fastClk;
    ClockGen #(
        .FREQ(FastClkFreq),
        .DIVR(1),
        .DIVF(68),
        .DIVQ(2),
        .FILTER_RANGE(1)
    ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(fastClk));
    
    // ====================
    // Slow Clock (375 kHz)
    // ====================
    reg[5:0] counter = 0;
    always @(posedge clk24mhz) begin
        counter <= counter+1;
    end
    wire slowClk = counter[$size(counter)-1];
    
    // ====================
    // Nets
    // ====================
    assign led[3:0] = {4{fastClk}};
    assign sd_clk = fastClk;
    assign sd_cmd = fastClk;
    assign sd_dat[3:0] = {4{fastClk}};
    assign sd_init = 1'b0;
endmodule

// Test states


// ICE_SD_INIT = 0
//
//  ICE_SD_INIT     constant 0          √
//  ICE_SD_CLK      oscillating 1.8V    √
//  ICE_SD_CMD      oscillating 1.8V    √
//  ICE_SD_DAT0     oscillating 1.8V    √
//  ICE_SD_DAT1     oscillating 1.8V    √
//  ICE_SD_DAT2     oscillating 1.8V    √
//  ICE_SD_DAT3     oscillating 1.8V    √
//  
//  SD_CLK          oscillating 1.8V    √
//  SD_CMD          oscillating 1.8V    √
//  SD_DAT0         oscillating 1.8V    √
//  SD_DAT1         oscillating 1.8V    √
//  SD_DAT2         oscillating 1.8V    √
//  SD_DAT3         oscillating 1.8V    √



// ICE_SD_INIT = 1
//
//  ICE_SD_INIT     constant 1          √
//  ICE_SD_CLK      oscillating 1.8V    √
//  ICE_SD_CMD      oscillating 1.8V    √
//  ICE_SD_DAT0     oscillating 1.8V    √
//  ICE_SD_DAT1     oscillating 1.8V    √
//  ICE_SD_DAT2     oscillating 1.8V    √
//  ICE_SD_DAT3     oscillating 1.8V    √
//  
//  SD_CLK          oscillating 2.8V    √
//  SD_CMD          oscillating 2.8V    √
//  SD_DAT0         constant 2.8V       √
//  SD_DAT1         constant 2.8V       √
//  SD_DAT2         constant 2.8V       √
//  SD_DAT3         constant 2.8V       √
