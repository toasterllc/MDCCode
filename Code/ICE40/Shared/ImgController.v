`ifndef ImgController_v
`define ImgController_v

`include "RAMController.v"
`include "TogglePulse.v"
`include "AFIFO.v"

module ImgController #(
    parameter ClkFreq = 24_000_000,
    parameter ImageWidthMax = 256,
    parameter ImageHeightMax = 256,
    parameter HeaderWidth = 128
)(
    input wire          clk,
    
    // Command port (clock domain: `clk`)
    input wire                  cmd_capture,    // Toggle
    input wire[0:0]             cmd_ramBlock,
    input wire[HeaderWidth-1:0] cmd_header,
    
    // Readout port (clock domain: `readout_clk`)
    input wire          readout_clk,
    output wire         readout_ready,
    input wire          readout_trigger,
    output wire[15:0]   readout_data,
    
    // Status port (clock domain: `clk`)
    output reg                                  status_captureDone = 0, // Toggle
    output wire[`RegWidth(ImageWidthMax)-1:0]   status_captureImageWidth,
    output wire[`RegWidth(ImageHeightMax)-1:0]  status_captureImageHeight,
    output wire[17:0]                           status_captureHighlightCount,
    output wire[17:0]                           status_captureShadowCount,
    
    // Img port (clock domain: `img_dclk`)
    input wire          img_dclk,
    input wire[11:0]    img_d,
    input wire          img_fv,
    input wire          img_lv,
    
    // RAM port (clock domain: `ram_clk`)
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[11:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    localparam ImageSizeMax = ImageWidthMax*ImageHeightMax;
    
    // ====================
    // RAMController
    // ====================
    reg[0:0]    ramctrl_cmd_block = 0;
    reg[1:0]    ramctrl_cmd = 0;
    wire        ramctrl_write_ready;
    reg         ramctrl_write_trigger = 0;
    reg[15:0]   ramctrl_write_data = 0;
    wire        ramctrl_read_ready;
    wire        ramctrl_read_trigger;
    wire[15:0]  ramctrl_read_data;
    
    RAMController #(
        .ClkFreq(ClkFreq),
        .BlockSize(ImageSizeMax)
    ) RAMController (
        .clk(clk),
        
        .cmd(ramctrl_cmd),
        .cmd_block(ramctrl_cmd_block),
        
        .write_ready(ramctrl_write_ready),
        .write_trigger(ramctrl_write_trigger),
        .write_data(ramctrl_write_data),
        
        .read_ready(ramctrl_read_ready),
        .read_trigger(ramctrl_read_trigger),
        .read_data(ramctrl_read_data),
        
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
    // Input FIFO (Pixels->RAM)
    // ====================
    reg fifoIn_rst = 0;
    wire fifoIn_write_ready;
    wire fifoIn_write_trigger;
    wire[15:0] fifoIn_write_data;
    wire fifoIn_read_ready;
    wire fifoIn_read_trigger;
    wire[15:0] fifoIn_read_data;
    
    AFIFO AFIFO_fifoIn(
        .rst_(!fifoIn_rst),
        
        .w_clk(img_dclk),
        .w_ready(fifoIn_write_ready),
        .w_trigger(fifoIn_write_trigger),
        .w_data(fifoIn_write_data),
        
        .r_clk(clk),
        .r_ready(fifoIn_read_ready),
        .r_trigger(fifoIn_read_trigger),
        .r_data(fifoIn_read_data)
    );
    
    // ====================
    // Output FIFO (RAM->Output)
    // ====================
    reg fifoOut_rst = 0;
    wire fifoOut_write_ready;
    wire fifoOut_write_trigger;
    wire[15:0] fifoOut_write_data;
    wire fifoOut_read_ready;
    wire fifoOut_read_trigger;
    wire[15:0] fifoOut_read_data;
    
    AFIFO AFIFO_fifoOut(
        .rst_(!fifoOut_rst),
        
        .w_clk(clk),
        .w_ready(fifoOut_write_ready),
        .w_trigger(fifoOut_write_trigger),
        .w_data(fifoOut_write_data),
        
        .r_clk(readout_clk),
        .r_ready(fifoOut_read_ready),
        .r_trigger(fifoOut_read_trigger),
        .r_data(fifoOut_read_data)
    );
    
    // ====================
    // Pin: img_d
    // ====================
    genvar i;
    wire[11:0] img_d_reg;
    for (i=0; i<12; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b0000_00)
        ) SB_IO_img_d (
            .INPUT_CLK(img_dclk),
            .PACKAGE_PIN(img_d[i]),
            .D_IN_0(img_d_reg[i])
        );
    end
    
    // ====================
    // Pin: img_fv
    // ====================
    wire img_fv_reg;
    SB_IO #(
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_img_fv (
        .INPUT_CLK(img_dclk),
        .PACKAGE_PIN(img_fv),
        .D_IN_0(img_fv_reg)
    );
    
    // ====================
    // Pin: img_lv
    // ====================
    wire img_lv_reg;
    SB_IO #(
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_img_lv (
        .INPUT_CLK(img_dclk),
        .PACKAGE_PIN(img_lv),
        .D_IN_0(img_lv_reg)
    );
    
    // ====================
    // Pixel input state machine
    // ====================
    reg fifoIn_writeEn = 0;
    
    reg ctrl_fifoInCaptureTrigger = 0;
    `TogglePulse(fifoIn_captureTrigger, ctrl_fifoInCaptureTrigger, posedge, img_dclk);
    
    reg fifoIn_started = 0;
    `TogglePulse(ctrl_fifoInStarted, fifoIn_started, posedge, clk);
    
    reg[`RegWidth(ImageWidthMax)-1:0] fifoIn_imageWidth = 0;
    reg[`RegWidth(ImageHeightMax)-1:0] fifoIn_imageHeight = 0;
    reg[17:0] fifoIn_highlightCount = 0;
    reg[17:0] fifoIn_shadowCount = 0;
    assign status_captureImageWidth = fifoIn_imageWidth;
    assign status_captureImageHeight = fifoIn_imageHeight;
    assign status_captureHighlightCount = fifoIn_highlightCount;
    assign status_captureShadowCount = fifoIn_shadowCount;
    
    wire fifoIn_lv = img_lv_reg;
    wire fifoIn_fv = img_fv_reg;
    reg fifoIn_lvPrev = 0;
    reg[1:0] fifoIn_x = 0;
    reg[1:0] fifoIn_y = 0;
    reg fifoIn_countStat = 0;
    reg[11:0] fifoIn_countStatPx = 0;
    
    reg fifoIn_done = 0;
    // `TogglePulse(ctrl_fifoInDone, fifoIn_done, posedge, clk);
    // `ToggleAck(ctrl_fifoInDone, ctrl_fifoInDoneAck, fifoIn_done, posedge, clk);
    `Sync(ctrl_fifoInDone, fifoIn_done, posedge, clk);
    
    reg[2:0] fifoIn_state = 0;
    always @(posedge img_dclk) begin
        fifoIn_rst <= 0; // Pulse
        fifoIn_writeEn <= 0; // Reset by default
        fifoIn_lvPrev <= fifoIn_lv;
        
        if (fifoIn_write_trigger) begin
            // Count the width of the image
            if (!fifoIn_lvPrev) fifoIn_imageWidth <= 1;
            else                fifoIn_imageWidth <= fifoIn_imageWidth+1;
            // Count the height of the image
            if (!fifoIn_lvPrev) fifoIn_imageHeight <= fifoIn_imageHeight+1;
        end
        
        if (!fifoIn_lv) fifoIn_x <= 0;
        else            fifoIn_x <= fifoIn_x+1;
        
        if (!fifoIn_fv)                         fifoIn_y <= 0;
        else if (fifoIn_lvPrev && !fifoIn_lv)   fifoIn_y <= fifoIn_y+1;
        
        // Count pixel stats (number of highlights/shadows)
        // We're pipelining `fifoIn_countStat` and `fifoIn_countStatPx` here for performance
        fifoIn_countStat <= (fifoIn_write_trigger && !fifoIn_x && !fifoIn_y);
        fifoIn_countStatPx <= img_d_reg;
        if (fifoIn_countStat) begin
            // Look at the high bits to determine if it's a highlight or shadow
            case (`LeftBits(fifoIn_countStatPx, 0, 7))
            // Highlight
            7'b111_1111:   fifoIn_highlightCount <= fifoIn_highlightCount+1;
            // Shadow
            7'b000_0000:   fifoIn_shadowCount <= fifoIn_shadowCount+1;
            endcase
        end
        
        case (fifoIn_state)
        // Idle: wait to be triggered
        0: begin
        end
        
        // Reset FIFO / ourself
        1: begin
            fifoIn_rst <= 1;
            fifoIn_done <= 0;
            fifoIn_imageWidth <= 0;
            fifoIn_imageHeight <= 0;
            fifoIn_highlightCount <= 0;
            fifoIn_shadowCount <= 0;
            fifoIn_state <= 2;
        end
        
        // Wait for FIFO to be done resetting
        2: begin
            if (!fifoIn_rst) begin
                fifoIn_started <= !fifoIn_started;
                fifoIn_state <= 3;
            end
        end
        
        // Wait for the frame to be invalid
        3: begin
            if (!img_fv_reg) begin
                $display("[ImgController:FIFO] Waiting for frame invalid...");
                fifoIn_state <= 4;
            end
        end
        
        // Wait for the frame to start
        4: begin
            if (img_fv_reg) begin
                $display("[ImgController:FIFO] Frame start");
                fifoIn_state <= 5;
            end
        end
        
        // Wait until the end of the frame
        5: begin
            fifoIn_writeEn <= 1;
            
            if (!img_fv_reg) begin
                $display("[ImgController:FIFO] Frame end");
                fifoIn_done <= 1;
                fifoIn_state <= 0;
            end
        end
        endcase
        
        if (fifoIn_captureTrigger) begin
            fifoIn_state <= 1;
        end
    end
    
    // ====================
    // Control State Machine
    // ====================
    `TogglePulse(ctrl_cmdCapture, cmd_capture, posedge, clk);
    // TODO: try storing ctrl_imageWidth / ctrl_imageHeight in their own registers
    wire[`RegWidth(ImageWidthMax)-1:0] ctrl_imageWidth = fifoIn_imageWidth;
    wire[`RegWidth(ImageHeightMax)-1:0] ctrl_imageHeight = fifoIn_imageHeight;
    reg[`RegWidth(ImageSizeMax)-1:0] ctrl_readoutCount = 0;
    reg ctrl_fifoOutWrote = 0;
    reg ctrl_fifoOutLastPixel = 0;
    reg ctrl_fifoOutDone = 0;
    reg[HeaderWidth-1:0] ctrl_cmdHeader = 0;
    
    localparam HeaderWordCount = HeaderWidth/16;
    reg[`RegWidth(HeaderWordCount-1)-1:0] ctrl_cmdHeaderCount = 0;
    
    localparam Ctrl_State_Idle          = 0; // +0
    localparam Ctrl_State_WriteHeader   = 1; // +1
    localparam Ctrl_State_Capture       = 3; // +2
    localparam Ctrl_State_Readout       = 6; // +2
    localparam Ctrl_State_Count         = 9;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ramctrl_cmd <= `RAMController_Cmd_None;
        fifoOut_rst <= 0;
        ramctrl_write_trigger <= 0;
        
        ctrl_fifoOutWrote <= fifoOut_write_ready && fifoOut_write_trigger;
        if (ctrl_fifoOutWrote) begin
            $display("[ImgController] ctrl_readoutCount: %0d", ctrl_readoutCount);
            ctrl_readoutCount <= ctrl_readoutCount-1;
            if (ctrl_readoutCount === 0) begin
                ctrl_fifoOutLastPixel <= 1;
            end
        end
        
        // Stop reading from RAM when we reach the last pixel
        if (fifoOut_write_ready && fifoOut_write_trigger && ctrl_fifoOutLastPixel) begin
            ctrl_fifoOutDone <= 1;
        end
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
        end
        
        Ctrl_State_WriteHeader: begin
            $display("[ImgController:WriteHeader] Triggered");
            // Supply 'Write' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Write;
            ramctrl_write_data <= `LeftBits(cmd_header, 0, 16);
            ctrl_cmdHeader <= cmd_header<<16;
            ctrl_cmdHeaderCount <= HeaderWordCount-1;
            $display("[ImgController:WriteHeader] Waiting for RAMController to be ready to write...");
            ctrl_state <= Ctrl_State_WriteHeader+1;
        end
        
        Ctrl_State_WriteHeader+1: begin
            ramctrl_write_trigger <= 1;
            // Wait for the write command to be consumed, and for the RAMController
            // to be ready to write.
            if (ramctrl_cmd===`RAMController_Cmd_None && ramctrl_write_ready) begin
                $display("[ImgController:WriteHeader] Wrote header word %0d/%0d",
                    HeaderWordCount-ctrl_cmdHeaderCount, HeaderWordCount);
                
                ramctrl_write_data <= `LeftBits(ctrl_cmdHeader, 0, 16);
                ctrl_cmdHeader <= ctrl_cmdHeader<<16;
                ctrl_cmdHeaderCount <= ctrl_cmdHeaderCount-1;
                if (!ctrl_cmdHeaderCount) begin
                    ramctrl_write_trigger <= 0;
                    ctrl_state <= Ctrl_State_Capture;
                end
            end
        end
        
        Ctrl_State_Capture: begin
            $display("[ImgController:Capture] Waiting for FIFO to reset...");
            // Start the FIFO data flow now that RAMController is ready to write
            ctrl_fifoInCaptureTrigger <= !ctrl_fifoInCaptureTrigger;
            ctrl_state <= Ctrl_State_Capture+1;
        end
        
        Ctrl_State_Capture+1: begin
            // Wait for the fifoIn state machine to start
            if (ctrl_fifoInStarted) begin
                ctrl_state <= Ctrl_State_Capture+2;
            end
        end
        
        Ctrl_State_Capture+2: begin
            // By default, prevent `ramctrl_write_trigger` from being reset
            ramctrl_write_trigger <= ramctrl_write_trigger;
            
            // Reset `ramctrl_write_trigger` if RAMController accepted the data
            if (ramctrl_write_ready && ramctrl_write_trigger) begin
                ramctrl_write_trigger <= 0;
            end
            
            // Copy word from FIFO->RAM
            if (fifoIn_read_ready && fifoIn_read_trigger) begin
                // $display("[ImgController:Capture] Got pixel: %0d", fifoIn_read_data);
                ramctrl_write_data <= fifoIn_read_data;
                ramctrl_write_trigger <= 1;
            end
            
            // We're finished when the FIFO doesn't have data, and the fifoIn state
            // machine signals that it's done receiving data.
            if (!fifoIn_read_ready && ctrl_fifoInDone) begin
                $display("[ImgController:Capture] Finished");
                ctrl_state <= Ctrl_State_Readout;
            end
        end
        
        Ctrl_State_Readout: begin
            $display("[ImgController:Readout] Started");
            // Supply 'Read' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Read;
            // Reset output FIFO
            fifoOut_rst <= 1;
            // Reset readout state
`ifdef SIM
            ctrl_readoutCount <= 64*32+HeaderWordCount-3;
`else
            ctrl_readoutCount <= 2304*1296+HeaderWordCount-3;
`endif
            // ctrl_readoutCount <= ImageSizeMax;
            ctrl_fifoOutLastPixel <= 0;
            ctrl_fifoOutDone <= 0;
            ctrl_state <= Ctrl_State_Readout+1;
        end
        
        Ctrl_State_Readout+1: begin
            // Wait for the read command and FIFO reset to be consumed
            if (ramctrl_cmd===`RAMController_Cmd_None && !fifoOut_rst) begin
                status_captureDone <= !status_captureDone;
                ctrl_state <= Ctrl_State_Readout+2;
            end
        end
        
        Ctrl_State_Readout+2: begin
            if (ctrl_fifoOutDone) begin
                ramctrl_cmd <= `RAMController_Cmd_Stop;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        endcase
        
        if (ctrl_cmdCapture) ctrl_state <= Ctrl_State_WriteHeader;
    end
    
    // ====================
    // Connections
    // ====================
    // Connect input FIFO write -> pixel data
    assign fifoIn_write_trigger = fifoIn_writeEn && img_lv_reg;
    assign fifoIn_write_data = {4'b0, img_d_reg};
    
    // Connect input FIFO read -> RAM write
    assign fifoIn_read_trigger = (!ramctrl_write_trigger || ramctrl_write_ready);
    
    // Connect RAM read -> output FIFO write
    assign fifoOut_write_trigger = ramctrl_read_ready && !ctrl_fifoOutDone;
    assign ramctrl_read_trigger = fifoOut_write_ready;
    assign fifoOut_write_data = ramctrl_read_data;
    
    // Connect output FIFO read -> readout port
    assign readout_ready = fifoOut_read_ready;
    assign fifoOut_read_trigger = readout_trigger;
    assign readout_data = fifoOut_read_data;
    
endmodule

`endif
