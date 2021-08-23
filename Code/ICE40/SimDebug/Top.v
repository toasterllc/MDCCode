`include "Util.v"

`timescale 1ns/1ps

module Testbench #(
    parameter W = 16 // Word width; allowed values: 16, 8, 4, 2
)();
// `ifdef SIM
//     if ()
// `endif
//
    // initial $error("hello");
    // $assert(W == 8);
    
    wire[3:0] hello;
    
    // assign hello[3] = 1'b0;
    // assign hello[0] = 1'b0;
    assign {hello[3], hello[0]} = ~0;
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        #1;
        $display("%b", hello);
        $display("%0d", `RegWidth((4096/W)-1));
        $finish;
    end
endmodule
