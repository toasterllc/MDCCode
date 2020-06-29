`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    output wire[3:0]    led,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do,
);
    wire clk = clk12mhz;
    
    // reg tmp = 0;
    // assign led[0] = tmp;
    
    reg[23:0] counter = 0;
    // assign led[3:0] = counter[11: 8];
    // assign led[3:0] = counter[ 7: 4];
    assign led[3:0] = counter[ 3: 0];
    
    // assign led[3:0] = {4{counter == 35}};
    // assign led[3:0] = {4{counter == 0}};
    
    always @(posedge debug_clk) begin
        if (debug_cs) begin
            counter <= counter+1;
        end
    end
    
    // assign led[3:0] = 4'b1111;
    
endmodule
