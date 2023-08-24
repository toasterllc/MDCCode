`define ICEApp_STM_En
`define ICEApp_SDReadoutToSPI_En
`include "ICEApp.v"

`ifdef SIM
`include "ICEAppSim.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    // STM SPI port
    input wire          ice_stm_spi_clk,
    input wire          ice_stm_spi_cs_,
    inout wire[7:0]     ice_stm_spi_d,
    output wire         ice_stm_spi_d_ready,
    output wire         ice_stm_spi_d_ready_rev4bodge,
    
    // SD port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    output wire         sd_pullup_1v8_en_,
    
    // LED port
    output wire[1:0]    ice_led
    
`ifdef SIM
    // Exported so that the sim can verify that the state machine is in reset
    , output wire         sim_spiRst_
`endif
);
    ICEApp ICEApp(.*);
endmodule
