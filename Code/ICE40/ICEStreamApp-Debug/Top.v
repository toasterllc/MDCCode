// TODO: investigate whether our various toggle signals that cross clock domains are safe (such as sd_ctrl_cmdTrigger).
// currently we syncronize the toggled signal across clock domains, and assume that all dependent signals
// (sd_ctrl_cmdRespType_48, sd_ctrl_cmdRespType_136) have settled by the time the toggled signal lands in the destination
// clock domain. but if the destination clock is fast enough relative to the source clock, couldn't the destination
// clock observe the toggled signal before the dependent signals have settled?
// we should probably delay the toggle signal by 1 cycle in the source clock domain, to guarantee that all the
// dependent signals have settled in the source clock domain.

`include "Sync.v"
`include "TogglePulse.v"
`include "ToggleAck.v"
`include "ClockGen.v"
`include "PixController.v"
`include "PixI2CMaster.v"
`include "RAMController.v"
`include "ICEAppTypes.v"

`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    
    input wire          spi_clk,
    input wire          spi_cs_,
    inout wire[7:0]     spi_d,
    
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    output reg          pix_rst_ = 0,
    output wire         pix_sclk,
    inout wire          pix_sdata,
    
    // RAM port
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    // ====================
    // PixI2CMaster
    // ====================
    localparam PixI2CSlaveAddr = 7'h10;
    reg pixi2c_cmd_write = 0;
    reg[15:0] pixi2c_cmd_regAddr = 0;
    reg pixi2c_cmd_dataLen = 0;
    reg[15:0] pixi2c_cmd_writeData = 0;
    reg pixi2c_cmd_trigger = 0;
    wire pixi2c_status_done;
    wire pixi2c_status_err;
    wire[15:0] pixi2c_status_readData;
    `ToggleAck(spi_pixi2c_done_, spi_pixi2c_doneAck, pixi2c_status_done, posedge, spi_clk);
    
    PixI2CMaster #(
        .ClkFreq(24_000_000),
        .I2CClkFreq(100_000) // TODO: try 400_000 (the max frequency) to see if it works. if not, the pullup's likely too weak.
    ) PixI2CMaster (
        .clk(clk24mhz),
        
        .cmd_slaveAddr(PixI2CSlaveAddr),
        .cmd_write(pixi2c_cmd_write),
        .cmd_regAddr(pixi2c_cmd_regAddr),
        .cmd_dataLen(pixi2c_cmd_dataLen),
        .cmd_writeData(pixi2c_cmd_writeData),
        .cmd_trigger(pixi2c_cmd_trigger), // Toggle
        
        .status_done(pixi2c_status_done), // Toggle
        .status_err(pixi2c_status_err),
        .status_readData(pixi2c_status_readData),
        
        .i2c_clk(pix_sclk),
        .i2c_data(pix_sdata)
    );
    
    
    
    
    
    
    
    // ====================
    // Pix Clock (108 MHz)
    // ====================
    localparam Pix_Clk_Freq = 108_000_000;
    wire pix_clk;
    ClockGen #(
        .FREQ(Pix_Clk_Freq),
        .DIVR(0),
        .DIVF(35),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_pix_clk(.clkRef(clk24mhz), .clk(pix_clk));
    
    // ====================
    // PixController
    // ====================
    reg[1:0]                            pixctrl_cmd = 0;
    reg[2:0]                            pixctrl_cmd_ramBlock = 0;
    wire                                pixctrl_readout_clk;
    wire                                pixctrl_readout_ready;
    wire                                pixctrl_readout_trigger;
    wire[15:0]                          pixctrl_readout_data;
    wire                                pixctrl_status_captureDone;
    wire[`RegWidth(ImageWidthMax)-1:0]  pixctrl_status_captureImageWidth;
    wire[`RegWidth(ImageHeightMax)-1:0] pixctrl_status_captureImageHeight;
    wire[17:0]                          pixctrl_status_captureHighlightCount;
    wire[17:0]                          pixctrl_status_captureShadowCount;
    wire                                pixctrl_status_readoutStarted;
    PixController #(
        .ClkFreq(Pix_Clk_Freq),
        .ImageWidthMax(ImageWidthMax),
        .ImageHeightMax(ImageHeightMax)
    ) PixController (
        .clk(pix_clk),
        
        .cmd(pixctrl_cmd),
        .cmd_ramBlock(pixctrl_cmd_ramBlock),
        
        .readout_clk(pixctrl_readout_clk),
        .readout_ready(pixctrl_readout_ready),
        .readout_trigger(pixctrl_readout_trigger),
        .readout_data(pixctrl_readout_data),
        
        .status_captureDone(pixctrl_status_captureDone),
        .status_captureImageWidth(pixctrl_status_captureImageWidth),
        .status_captureImageHeight(pixctrl_status_captureImageHeight),
        .status_captureHighlightCount(pixctrl_status_captureHighlightCount),
        .status_captureShadowCount(pixctrl_status_captureShadowCount),
        .status_readoutStarted(pixctrl_status_readoutStarted),
        
        .pix_dclk(pix_dclk),
        .pix_d(pix_d),
        .pix_fv(pix_fv),
        .pix_lv(pix_lv),
        
        .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq)
    );
endmodule
