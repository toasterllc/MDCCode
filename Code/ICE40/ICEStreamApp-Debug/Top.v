`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    input wire          pix_dclk,
    inout wire          pix_x,
    inout wire          pix_y
);
    reg pix_x_do = 0;
    wire pix_x_di;
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) IO_A (
        .INPUT_CLK(clk24mhz),
        .OUTPUT_CLK(clk24mhz),
        .PACKAGE_PIN(pix_x),
        .OUTPUT_ENABLE(1'b1),
        .D_OUT_0(pix_x_do),
        .D_IN_0(pix_x_di)
    );
    
    reg pix_y_do = 0;
    wire pix_y_di;
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) IO_B (
        .INPUT_CLK(pix_dclk),
        .OUTPUT_CLK(pix_dclk),
        .PACKAGE_PIN(pix_y),
        .OUTPUT_ENABLE(1'b1),
        .D_OUT_0(pix_y_do),
        .D_IN_0(pix_y_di)
    );
endmodule
