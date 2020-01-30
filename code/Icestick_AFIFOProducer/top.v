`timescale 1ns/1ps
`include "../ClockGen.v"

module Icestick_AFIFOProducer(
    input wire clk12mhz,
    output wire wclk,
    output reg w,
    output reg[11:0] wd
);
    
    wire clk;
    
    // 16 MHz clock
    ClockGen #(
        .FREQ(16),
		.DIVR(0),
		.DIVF(84),
		.DIVQ(6),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst());
    
    reg[25:0] delayCounter;
    wire delay = !(&delayCounter);
    
    reg[13:0] wclkCounter;
    assign wclk = wclkCounter[$size(wclkCounter)-1];
    reg wclkLast;
    
    // Produce values
    always @(posedge clk) begin
        if (delay) begin
            delayCounter <= delayCounter+1;
        
        end else begin
            if (wclk & !wclkLast) begin
                if (w) begin
                    // We wrote a value, continue to the next one
                    $display("Wrote value: %h", wd);
                end
                
                w <= 1;
                wd <= wd+1'b1;
                wclkLast <= 1;
            end else if (!wclk & wclkLast) begin
                wclkLast <= 0;
            end
            
            wclkCounter <= wclkCounter+1;
        end
    end
    
endmodule
