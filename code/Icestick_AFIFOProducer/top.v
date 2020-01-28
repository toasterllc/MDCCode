`timescale 1ns/1ps

module Icestick_AFIFOProducer(
    input wire clk12mhz,
    output wire clk,
    output reg w = 0,
    output reg[11:0] wd = 0
);
    
`ifdef SIM
    reg[7:0] clkDivider = 0;
`else
    reg[12:0] clkDivider = 0;
`endif
    
    always @(posedge clk12mhz) clkDivider <= clkDivider+1;
    assign clk = clkDivider[$size(clkDivider)-1];
    
    reg[1:0] rstCounter = 0;
    wire rst = !(&rstCounter);
    always @(posedge clk)
        if (rst)
            rstCounter <= rstCounter+1;
    
    // Produce values
    always @(posedge clk) begin
        if (!rst) begin
            if (w) begin
                // We wrote a value, continue to the next one
                $display("Wrote value: %h", wd);
            end
            
            w <= 1;
            wd <= wd+1'b1;
        end
    end
endmodule
