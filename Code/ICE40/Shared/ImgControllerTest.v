`ifndef ImgControllerTest_v
`define ImgControllerTest_v

`include "ImgController.v"
`include "ClockGen.v"
`include "ICEAppTypes.v"
`timescale 1ns/1ps

// MOBILE_SDR_INIT_VAL: Initialize the memory because ImgController reads a few words
// beyond the image that's written to the RAM, and we don't want to read `x` (don't care)
// when that happens
`define MOBILE_SDR_INIT_VAL 16'hCAFE
`include "mt48h32m16lf/mobile_sdr.v"

module ImgControllerTest();
    // ReadoutFIFO_R_Thresh: Signal `readoutfifo_r_thresh` when >=1 FIFO is full (SDController
    // consumes 512-byte chunks)
    localparam ReadoutFIFO_R_Thresh = 1;
    // ImgCtrl_PaddingWordCount: padding so that ImgController readout outputs enough
    // data to trigger the AFIFOChain read threshold (`readoutfifo_r_thresh`)
    localparam ImgCtrl_AFIFOWordCapacity = (`AFIFO_CapacityBytes/2);
    localparam ImgCtrl_ReadoutWordThresh = ReadoutFIFO_R_Thresh*ImgCtrl_AFIFOWordCapacity;
    localparam ImgCtrl_PaddingWordCount = (ImgCtrl_ReadoutWordThresh - (`Img_WordCount % ImgCtrl_ReadoutWordThresh)) % ImgCtrl_ReadoutWordThresh;
    
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
    
    localparam Img_Clk_Freq = 108_000_000;
    wire img_clk;
    ClockGen #(
        .FREQOUT(Img_Clk_Freq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_img_clk(.clkRef(ice_img_clk16mhz), .clk(img_clk));
    
    reg                                     imgctrl_cmd_capture = 0;
    reg                                     imgctrl_cmd_readout = 0;
    reg[0:0]                                imgctrl_cmd_ramBlock = 0;
    reg[0:0]                                imgctrl_cmd_skipCount = 0;
    reg[`Img_HeaderWordCount*16-1:0]        imgctrl_cmd_header = {
        8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77,
        8'h88, 8'h99, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF,
        8'hFF, 8'hEE, 8'hDD, 8'hCC, 8'hBB, 8'hAA, 8'h99, 8'h88,
        8'h77, 8'h66, 8'h55, 8'h44, 8'h33, 8'h22, 8'h11, 8'h00
    };
    reg                                     imgctrl_cmd_thumb = 0;
    wire                                    imgctrl_readout_rst;
    wire                                    imgctrl_readout_start;
    wire                                    imgctrl_readout_ready;
    wire                                    imgctrl_readout_trigger = 1;
    wire[15:0]                              imgctrl_readout_data;
    
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
        
        .status_captureDone(),
        .status_capturePixelCount(),
        .status_captureHighlightCount(),
        .status_captureShadowCount(),
        
        .img_dclk(),
        .img_d(),
        .img_fv(),
        .img_lv(),
        
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
    
    task TestImgReadout(input[`Msg_Arg_ImgReadout_Thumb_Len-1:0] thumb); begin
        localparam ImageWordCount = `Img_HeaderWordCount + (`Img_Width*`Img_Height) + ImgCtrl_PaddingWordCount;
        localparam WaitForWordTimeoutNs = 10000000;
        integer recvWordCount;
        integer done;
        realtime lastWordTime;
        integer expectedWordCount;
        
        $display("\n========== TestImgReadout (thumb: %b) ==========", thumb);
        
        imgctrl_cmd_thumb = thumb;
        
        // Trigger readout
        imgctrl_cmd_readout = !imgctrl_cmd_readout;
        
        // Wait for readout to start
        recvWordCount = 0;
        done = 0;
        while (!done) begin
            wait(img_clk);
            if (imgctrl_readout_ready && imgctrl_readout_trigger) begin
                lastWordTime = $realtime;
                recvWordCount++;
            end
            wait(!img_clk);
            
            done = (
                recvWordCount>`Img_HeaderWordCount &&   // Only institute our wait logic after the header has been received
                $realtime-lastWordTime>WaitForWordTimeoutNs
            );
        end
        
        expectedWordCount = (!thumb ? `Img_WordCount : `Img_ThumbWordCount) + ImgCtrl_PaddingWordCount;
        if (recvWordCount === expectedWordCount) begin
            $display("Received word count: %0d (expected: %0d) ✅", recvWordCount, expectedWordCount);
        end else begin
            $display("Received word count: %0d (expected: %0d) ❌", recvWordCount, expectedWordCount);
            $finish;
        end
    end endtask
    
    // Actual test
    initial begin
        // Wait for clock to go high then low
        wait(img_clk);
        wait(!img_clk);
        
        TestImgReadout(1);
        
        // for (i=0; i<ImageWordCount; i++) begin
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
        $dumpfile("ImgControllerTest.vcd");
        $dumpvars(0, ImgControllerTest);
    end
    
endmodule
`endif // ImgControllerTest_v
