`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    input wire          ice_st_spi_clk,
    input wire          ice_st_spi_cs_,
    inout wire[7:0]     ice_st_spi_d,
    
    // LED port
    output reg[3:0]     ice_led = 0
);
    assign ice_st_spi_d = 0;
endmodule
