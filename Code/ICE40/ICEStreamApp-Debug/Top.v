`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    inout wire          pix_x,
    inout wire          pix_y
);
    reg pix_x_oe = 0;
    reg pix_x_do = 0;
    wire pix_x_di;
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) IO_A (
        .INPUT_CLK(clk24mhz),
        .OUTPUT_CLK(clk24mhz),
        .PACKAGE_PIN(pix_x),
        .OUTPUT_ENABLE(pix_x_oe),
        .D_OUT_0(pix_x_do),
        .D_IN_0(pix_x_di)
    );
    
    reg pix_y_oe = 0;
    reg pix_y_do = 0;
    wire pix_y_di;
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) IO_B (
        .INPUT_CLK(clk24mhz),
        .OUTPUT_CLK(clk24mhz),
        .PACKAGE_PIN(pix_y),
        .OUTPUT_ENABLE(pix_y_oe),
        .D_OUT_0(pix_y_do),
        .D_IN_0(pix_y_di)
    );
    
    reg[11:0] counter = 0;
    always @(posedge clk24mhz) begin
        counter <= counter+1;
        if (counter[11]) begin
            pix_x_do <= pix_y_di;
        end
        
        if (counter[10]) begin
            pix_y_do <= pix_x_di;
        end
        
        if (counter[9]) begin
            pix_x_oe <= !pix_x_oe;
        end
        
        if (counter[7]) begin
            pix_y_oe <= !pix_y_oe;
        end
    end
endmodule
