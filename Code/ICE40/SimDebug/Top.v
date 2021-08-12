`timescale 1ns/1ps

module Top(
    inout wire PACKAGE_PIN,
    input wire OUTPUT_ENABLE,
    input wire clk
);
    reg D_OUT = 0;
    SB_IO #(
        .PIN_TYPE(6'b1010_01)
    ) SB_IO (
        .PACKAGE_PIN(PACKAGE_PIN),
        .OUTPUT_ENABLE(OUTPUT_ENABLE),
        .D_OUT_0(D_OUT)
    );
    
    always @(posedge clk) begin
        D_OUT <= clk;
    end
endmodule
