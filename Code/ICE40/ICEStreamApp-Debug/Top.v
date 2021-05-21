`timescale 1ns/1ps

module Top(
    input wire          clkX,
    input wire          clkY,
    
    output wire         outX,
    output wire         outY
);
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) IO_A (
        .OUTPUT_CLK(clkX),
        .PACKAGE_PIN(outX),
        .OUTPUT_ENABLE(1),
        .D_OUT_0(0)
    );
    
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) IO_B (
        .OUTPUT_CLK(clkY),
        .PACKAGE_PIN(outY),
        .OUTPUT_ENABLE(1),
        .D_OUT_0(0)
    );
endmodule
