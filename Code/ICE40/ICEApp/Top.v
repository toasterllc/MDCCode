`include "Util.v"
`include "ToggleAck.v"
`include "ClockGen.v"
`include "ImgController.v"
`include "ICEAppTypes.v"

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    // IMG port
    input wire          img_dclk,
    input wire[11:0]    img_d,
    input wire          img_fv,
    input wire          img_lv,
    output reg          img_rst_ = 1'b1,
    
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
    output reg[3:0]     ice_led = 0
);
    // ====================
    // Img Clock (108 MHz)
    // ====================
    localparam Img_Clk_Freq = 108_000_000;
    wire img_clk;
    ClockGen #(
        .FREQOUT(Img_Clk_Freq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_img_clk(.clkRef(ice_img_clk16mhz), .clk(img_clk));
    
    // ====================
    // ImgController
    // ====================
    reg                                 imgctrl_cmd_capture = 0;
    reg[0:0]                            imgctrl_cmd_ramBlock = 0;
    wire                                imgctrl_readout_clk;
    wire                                imgctrl_readout_ready;
    wire                                imgctrl_readout_trigger;
    wire[15:0]                          imgctrl_readout_data;
    wire                                imgctrl_status_captureDone;
    wire[`RegWidth(ImageWidthMax)-1:0]  imgctrl_status_captureImageWidth;
    wire[`RegWidth(ImageHeightMax)-1:0] imgctrl_status_captureImageHeight;
    wire[17:0]                          imgctrl_status_captureHighlightCount;
    wire[17:0]                          imgctrl_status_captureShadowCount;
    ImgController #(
        .ClkFreq(Img_Clk_Freq),
        .ImageWidthMax(ImageWidthMax),
        .ImageHeightMax(ImageHeightMax)
    ) ImgController (
        .clk(img_clk),
        
        .cmd_capture(imgctrl_cmd_capture),
        .cmd_ramBlock(imgctrl_cmd_ramBlock),
        
        .readout_clk(imgctrl_readout_clk),
        .readout_ready(imgctrl_readout_ready),
        .readout_trigger(imgctrl_readout_trigger),
        .readout_data(imgctrl_readout_data),
        
        .status_captureDone(imgctrl_status_captureDone),
        .status_captureImageWidth(imgctrl_status_captureImageWidth),
        .status_captureImageHeight(imgctrl_status_captureImageHeight),
        .status_captureHighlightCount(imgctrl_status_captureHighlightCount),
        .status_captureShadowCount(imgctrl_status_captureShadowCount),
        
        .img_dclk(img_dclk),
        .img_d(img_d),
        .img_fv(img_fv),
        .img_lv(img_lv),
        
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
    
    
    
    
    
    
    
    
    
    
    
    `ToggleAck(spi_imgCaptureDone_, spi_imgCaptureDoneAck, imgctrl_status_captureDone, posedge, ice_img_clk16mhz);
    
    reg[3:0] debug_state = 0;
`ifdef SIM
    reg[7:0] debug_delay = 0;
`else
    reg[25:0] debug_delay = 0;
`endif
    always @(posedge ice_img_clk16mhz) begin
        ice_led <= {4{!spi_imgCaptureDone_}};
        
        if (debug_delay) begin
            debug_delay <= debug_delay-1;
        
        end else begin
            case (debug_state)
            0: begin
                if (!spi_imgCaptureDone_) spi_imgCaptureDoneAck <= !spi_imgCaptureDoneAck;
                debug_delay <= ~0;
                debug_state <= 1;
            end
            
            1: begin
                imgctrl_cmd_capture <= !imgctrl_cmd_capture;
                debug_state <= 2;
            end
            
            2: begin
            end
            endcase
        end
    end
endmodule
