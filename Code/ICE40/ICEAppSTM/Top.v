`define ICEApp_STM_En
`define ICEApp_SDReadoutToSPI_En
`include "ICEApp.v"

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    // STM SPI port
    input wire          ice_st_spi_clk,
    input wire          ice_st_spi_cs_,
    inout wire[7:0]     ice_st_spi_d,
    output wire         ice_st_spi_d_ready,
    output wire         ice_st_spi_d_ready_rev4bodge,
    
    // SD port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    
    // LED port
    output wire[3:0]    ice_led
    
`ifdef SIM
    // Exported so that the sim can verify that the state machine is in reset
    , output wire         sim_spiRst_
`endif
);
    ICEApp ICEApp(.*);
endmodule
