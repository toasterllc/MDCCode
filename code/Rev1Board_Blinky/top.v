`timescale 1ns/1ps

module Top(
    input wire clk12mhz,
    output wire[7:0]    led
);
    wire clk = clk12mhz;
    
	reg[20:0] counter = 0;
    always @(posedge clk) begin
		counter <= counter+1;
    end
	
	assign led[7:0] = {8{counter[$size(counter)-1]}};
endmodule
