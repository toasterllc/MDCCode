`define ICEApp_MSP_En
`define ICEApp_SDWrite_En
`define ICEApp_Img_En
`include "ICEApp.v"

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    // MSP SPI port
    input wire          ice_msp_spi_clk,
    inout wire          ice_msp_spi_data,
    
    // SD port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    
    // IMG port
    input wire          img_dclk,
    input wire[11:0]    img_d,
    input wire          img_fv,
    input wire          img_lv,
    output wire         img_rst_,
    output wire         img_sclk,
    inout wire          img_sdata,
    
    // RAM port
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[11:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq,
    
    // LED port
    output wire[3:0]     ice_led
    
`ifdef SIM
    // Exported so that the sim can verify that the state machine is in reset
    , output wire         sim_spiRst_
`endif
);
    ICEApp ICEApp(.*);
endmodule
