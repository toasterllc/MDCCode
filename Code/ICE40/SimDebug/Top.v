`include "Util.v"
`include "ImgController.v"

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
    
    wire[8:0] hello = 4'b1000;
    // wire[8:0] hello = 8'b11111000;
    
    // assign hello[3] = 1'b0;
    // assign hello[0] = 1'b0;
    // assign {hello[3], hello[0]} = ~0;
    
    // initial begin
    //     $dumpfile("Top.vcd");
    //     $dumpvars(0, Testbench);
    // end
    
    // initial begin
    //     #1;
    //     $display("%b", hello[0 +: 4]);
    //     $finish;
    // end
    
    
    initial begin
        $display("%b", {'0, hello});
        $finish;
    end
endmodule
