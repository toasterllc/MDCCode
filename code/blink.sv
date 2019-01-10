module main(input clk, output led1, output led2, output led3, output led4, output led5);
	logic[24:0] ctr;
    
	always_ff @(posedge clk)
		ctr <= ctr + 1;
    
	assign led1 = ctr[19];
	assign led2 = ctr[20];
	assign led3 = ctr[21];
	assign led4 = ctr[22];
	assign led5 = ctr[23];
endmodule
