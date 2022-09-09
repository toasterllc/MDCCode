`include "ImgController.v"
`include "ClockGen.v"
`include "ICEAppTypes.v"
`include "PixelValidator.v"
`include "ImgSim.v"
`timescale 1ns/1ps

// MOBILE_SDR_INIT_VAL: Initialize the memory because ImgController reads a few words
// beyond the image that's written to the RAM, and we don't want to read `x` (don't care)
// when that happens
`define MOBILE_SDR_INIT_VAL 16'hCAFE
`include "mt48h32m16lf/mobile_sdr.v"

module Top();
    // ReadoutFIFO_R_Thresh: Signal `readoutfifo_r_thresh` when >=1 FIFO is full (SDController
    // consumes 512-byte chunks)
    localparam ReadoutFIFO_R_Thresh = 1;
    // ImgCtrl_PaddingWordCount: padding so that ImgController readout outputs enough
    // data to trigger the AFIFOChain read threshold (`readoutfifo_r_thresh`)
    localparam ImgCtrl_AFIFOWordCapacity = (`AFIFO_CapacityBytes/2);
    localparam ImgCtrl_ReadoutWordThresh = ReadoutFIFO_R_Thresh*ImgCtrl_AFIFOWordCapacity;
    localparam ImgCtrl_PaddingWordCount = ImgCtrl_ReadoutWordThresh-1;
    
    // ====================
    // RAM
    // ====================
    wire        ram_clk;
    wire        ram_cke;
    wire[1:0]   ram_ba;
    wire[11:0]  ram_a;
    wire        ram_cs_;
    wire        ram_ras_;
    wire        ram_cas_;
    wire        ram_we_;
    wire[1:0]   ram_dqm;
    wire[15:0]  ram_dq;
    
    mobile_sdr mobile_sdr(
        .clk(ram_clk),
        .cke(ram_cke),
        .addr(ram_a),
        .ba(ram_ba),
        .cs_n(ram_cs_),
        .ras_n(ram_ras_),
        .cas_n(ram_cas_),
        .we_n(ram_we_),
        .dq(ram_dq),
        .dqm(ram_dqm)
    );
    
    // ====================
    // Clock
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
    // Image sensor
    // ====================
    wire        img_dclk;
    wire[11:0]  img_d;
    wire        img_fv;
    wire        img_lv;
    wire        img_rst_;
    
    ImgSim #(
        .ImgWidth(`Img_Width),
        .ImgHeight(`Img_Height)
    ) ImgSim (
        .img_dclk(img_dclk),
        .img_d(img_d),
        .img_fv(img_fv),
        .img_lv(img_lv),
        .img_rst_(img_rst_)
    );
    
    // ====================
    // ImgController
    // ====================
    reg                                     imgctrl_cmd_capture = 0;
    reg                                     imgctrl_cmd_readout = 0;
    reg[0:0]                                imgctrl_cmd_ramBlock = 0;
    reg[0:0]                                imgctrl_cmd_skipCount = 0;
    // reg[`Img_HeaderWordCount*16-1:0]        imgctrl_cmd_header = {
    //     8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77,
    //     8'h88, 8'h99, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF,
    //     8'hFF, 8'hEE, 8'hDD, 8'hCC, 8'hBB, 8'hAA, 8'h99, 8'h88,
    //     8'h77, 8'h66, 8'h55, 8'h44, 8'h33, 8'h22, 8'h11, 8'h00
    // };
    
    reg[`Img_HeaderWordCount*16-1:0]        imgctrl_cmd_header = 0;
    
    reg                                     imgctrl_cmd_thumb = 0;
    wire                                    imgctrl_readout_rst;
    wire                                    imgctrl_readout_start;
    wire                                    imgctrl_readout_ready;
    reg                                     imgctrl_readout_trigger = 0;
    wire[15:0]                              imgctrl_readout_data;
    
    wire                                    imgctrl_status_captureDone;
    wire[`RegWidth(`Img_WordCount)-1:0]     imgctrl_status_capturePixelCount;
    wire[17:0]                              imgctrl_status_captureHighlightCount;
    wire[17:0]                              imgctrl_status_captureShadowCount;
    
    ImgController #(
        .ClkFreq(Img_Clk_Freq),
        .HeaderWordCount(`Img_HeaderWordCount),
        .ImgWidth(`Img_Width),
        .ImgHeight(`Img_Height),
        .PaddingWordCount(ImgCtrl_PaddingWordCount)
    ) ImgController (
        .clk(img_clk),
        
        .cmd_capture(imgctrl_cmd_capture),
        .cmd_readout(imgctrl_cmd_readout),
        .cmd_ramBlock(imgctrl_cmd_ramBlock),
        .cmd_skipCount(imgctrl_cmd_skipCount),
        .cmd_header(imgctrl_cmd_header),
        .cmd_thumb(imgctrl_cmd_thumb),
        
        .readout_rst(imgctrl_readout_rst),
        .readout_start(imgctrl_readout_start),
        .readout_ready(imgctrl_readout_ready),
        .readout_trigger(imgctrl_readout_trigger),
        .readout_data(imgctrl_readout_data),
        
        .status_captureDone(imgctrl_status_captureDone),
        .status_capturePixelCount(imgctrl_status_capturePixelCount),
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
    
    // ====================
    // PixelValidator
    // ====================
    PixelValidator PixelValidator();
    
    task ImgCapture; begin
        integer imgctrl_status_captureDonePrev;
        $display("\n========== ImgCapture ==========");
        
        // Trigger capture
        imgctrl_status_captureDonePrev = imgctrl_status_captureDone;
        imgctrl_cmd_capture = !imgctrl_cmd_capture;
        
        // Wait until the capture is complete
        wait(imgctrl_status_captureDone !== imgctrl_status_captureDonePrev);
        
        $display("[ImgCapture] Capture done (done:%b pixelCount:%0d, highlightCount:%0d, shadowCount:%0d)",
            imgctrl_status_captureDone,
            imgctrl_status_capturePixelCount,
            imgctrl_status_captureHighlightCount,
            imgctrl_status_captureShadowCount,
        );
        
        if (imgctrl_status_capturePixelCount === `Img_PixelCount) begin
            $display("[ImgCapture] Pixel count: %0d (expected: %0d) ✅", imgctrl_status_capturePixelCount, `Img_PixelCount);
        end else begin
            $display("[ImgCapture] Pixel count: %0d (expected: %0d) ❌", imgctrl_status_capturePixelCount, `Img_PixelCount);
            $finish;
        end
    end endtask
    
    task ImgReadout(input[`Msg_Arg_ImgReadout_Thumb_Len-1:0] thumb); begin
        localparam ImgPixelInitial      = 16'h0FFF;
        localparam ImgPixelDelta        = -1;
        localparam WaitForWordTimeoutNs = 10000000;
        integer recvWordCount;
        integer done;
        realtime lastWordTime;
        integer expectedWordCount;
        
        $display("\n========== ImgReadout (thumb: %b) ==========", thumb);
        
        PixelValidator.Config(
            `Img_HeaderWordCount,                       // headerWordCount
            (!thumb ? `Img_Width : `Img_ThumbWidth),    // imageWidth
            (!thumb ? `Img_Height : `Img_ThumbHeight),  // imageHeight
            2,                                          // checksumWordCount
            ImgCtrl_PaddingWordCount,                   // paddingWordCount
            1,                                          // pixelValidate
            ImgPixelInitial,                            // pixelInitial
            ImgPixelDelta,                              // pixelDelta
            (!thumb ? 1 : 8),                           // pixelFilterPeriod
            (!thumb ? 1 : 2)                            // pixelFilterKeep
        );
        
        imgctrl_cmd_thumb = thumb;
        
        // Trigger readout
        imgctrl_cmd_readout = !imgctrl_cmd_readout;
        
        // Wait for readout to start
        recvWordCount = 0;
        done = 0;
        imgctrl_readout_trigger = 1;
        while (!done) begin
            wait(img_clk);
            if (imgctrl_readout_ready && imgctrl_readout_trigger) begin
                PixelValidator.Validate(imgctrl_readout_data);
                lastWordTime = $realtime;
                recvWordCount++;
            end
            wait(!img_clk);
            
            imgctrl_readout_trigger = $random&1;
            
            done = (
                recvWordCount>`Img_HeaderWordCount &&   // Only institute our timeout after the header has been received
                $realtime-lastWordTime>WaitForWordTimeoutNs
            );
        end
        
        PixelValidator.Done();
    end endtask
    
    // Actual test
    initial begin
        integer i;
        // Wait for clock to go high then low
        wait(img_clk);
        wait(!img_clk);
        
        ImgCapture();
        
        for (i=0; i<5; i++) begin
            ImgReadout(1); // Readout thumbnail image
            ImgReadout(0); // Readout full-size image
        end
        
        // for (i=0; i<ImgWordCount; i++) begin
        //     wait(img_clk && imgctrl_readout_ready && imgctrl_readout_trigger);
        //     wait(!img_clk);
        // end
        //
        // for (i=0; i<1000; i++) begin
        //     wait(img_clk);
        //     wait(!img_clk);
        // end
        
        $finish;
    end
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Top);
    end
    
endmodule
