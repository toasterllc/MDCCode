`timescale 1ns/1ps

module Testbench();
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    wire PACKAGE_PIN;
    reg OUTPUT_ENABLE = 0;
    reg D_OUT = 0;
    wire D_IN;
    
    initial begin
        #1;
        OUTPUT_ENABLE = 1;
        #1;
        D_OUT = 0;
        #1;
        $finish;
    end
    
    SB_IO #(
        .PIN_TYPE(6'b1010_01) // Output: tristate; input: unregistered
    ) SB_IO (
        .PACKAGE_PIN(PACKAGE_PIN),
        .OUTPUT_ENABLE(OUTPUT_ENABLE),
        .D_OUT_0(D_OUT),
        .D_IN_0(D_IN)
    );
endmodule
