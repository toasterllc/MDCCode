`timescale 1ns/1ps

module Top(
    input wire clk12mhz,
    output wire[3:0] led
);
        wire clk = clk12mhz;

    reg[20:0] counter = 0;
        always @(posedge clk) begin
        counter <= counter+1;
        end

    assign led[3:0] = {4{counter[$size(counter)-1]}};

    // assign led[3:0] = 4'b1111;
    
endmodule
