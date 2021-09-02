`include "Util.v"

`timescale 1ns/1ps

module Testbench();
    wire[1:0] hello = 2'b00;
    
    initial begin
        #1;
        $display("%b", hello);
        
        if (hello) begin
            $display("HELLO");
        end
        
        $finish;
    end
endmodule
