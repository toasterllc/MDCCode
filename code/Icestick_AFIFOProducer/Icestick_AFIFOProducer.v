`timescale 1ns/1ps

module Icestick_AFIFOProducer(
    input wire clk,
    output wire wclk,
    output reg w = 0,
    output reg[11:0] wd = 0
);
    
`ifdef SIM
    // Under simulation, wait less time before starting to produce values
    reg[3:0] delayCounter = 0;
`else
    reg[25:0] delayCounter = 0;
`endif
    wire delay = !(&delayCounter);
    
`ifdef SIM
    // Under simulation, use a smaller period between produced values so we don't have to simulate for long periods of time
    reg[3:0] wclkCounter = 0;
`else
    reg[13:0] wclkCounter = 0;
`endif
    
    assign wclk = wclkCounter[$size(wclkCounter)-1];
    reg wclkLast = 0;
    
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
