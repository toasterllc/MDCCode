`timescale 1ns/1ps

module Test_SB_IO (
	inout  PACKAGE_PIN,
	input  OUTPUT_ENABLE,
	input  D_OUT_0
);
	reg dout;
	always @* begin
    	dout = D_OUT_0;
	end
    
	generate
	    assign PACKAGE_PIN = OUTPUT_ENABLE ? dout : 1'bz;
	endgenerate
endmodule

module Top(PACKAGE_PIN, OUTPUT_ENABLE, clk);
  reg D_OUT = 0;
  input OUTPUT_ENABLE;
  inout PACKAGE_PIN;
  input clk;
  
  Test_SB_IO Test_SB_IO (
    .D_OUT_0(D_OUT),
    .OUTPUT_ENABLE(OUTPUT_ENABLE),
    .PACKAGE_PIN(PACKAGE_PIN)
  );
endmodule

module Testbench();
    wire PACKAGE_PIN;
    reg OUTPUT_ENABLE;
    wire clk = 0;
    Top Top(.*);
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
        
        #1;
        OUTPUT_ENABLE = 0;
        #1;
        OUTPUT_ENABLE = 1;
        #1;
        OUTPUT_ENABLE = 0;
        #1;
        OUTPUT_ENABLE = 1;
        #1;
        $finish;
    end
endmodule
