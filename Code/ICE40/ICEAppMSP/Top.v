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
    ICEApp ICEApp(
        .ice_img_clk16mhz(ice_img_clk16mhz),
        .ice_msp_spi_clk(ice_msp_spi_clk),
        .ice_msp_spi_data(ice_msp_spi_data),
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat),
        .img_dclk(img_dclk),
        .img_d(img_d),
        .img_fv(img_fv),
        .img_lv(img_lv),
        .img_rst_(img_rst_),
        .img_sclk(img_sclk),
        .img_sdata(img_sdata),
        .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq),
        .ice_led(ice_led)
        
`ifdef SIM
        , .sim_spiRst_(sim_spiRst_)
`endif
    );
endmodule
