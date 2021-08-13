`ifndef ImgController_v
`define ImgController_v

`include "RAMController.v"
`include "TogglePulse.v"
`include "AFIFO.v"

module ImgController #(
    parameter ClkFreq = 24_000_000,
    parameter ImageSizeMax = 256*256,
    parameter HeaderWidth = 128
)(
    input wire          clk,
    
    // Command port (clock domain: `clk`)
    input wire                              cmd_capture,    // Toggle
    input wire                              cmd_readout,    // Toggle
    input wire[0:0]                         cmd_ramBlock,
    input wire[HeaderWidth-1:0]             cmd_header,
    
    // Readout port (clock domain: `readout_clk`)
    input wire          readout_clk,
    output wire         readout_ready,
    input wire          readout_trigger,
    output wire[15:0]   readout_data,
    
    // Status port (clock domain: `clk`)
    output reg                                  status_captureDone = 0, // Toggle
    output wire[`RegWidth(ImageSizeMax)-1:0]    status_captureWordCount,
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
    localparam HeaderWordCount = HeaderWidth/16;
    
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
    reg fifoIn_write_trigger = 0;
    reg[15:0] fifoIn_write_data = 0;
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
    reg[`RegWidth(HeaderWordCount-1)-1:0] fifoIn_headerCount = 0;
    reg[HeaderWidth-1:0] fifoIn_header = 0;
    
    reg ctrl_fifoInCaptureTrigger = 0;
    `TogglePulse(fifoIn_captureTrigger, ctrl_fifoInCaptureTrigger, posedge, img_dclk);
    
    reg fifoIn_started = 0;
    `TogglePulse(ctrl_fifoInStarted, fifoIn_started, posedge, clk);
    
    reg[`RegWidth(ImageSizeMax)-1:0] fifoIn_wordCount = 0;
    reg[17:0] fifoIn_highlightCount = 0;
    reg[17:0] fifoIn_shadowCount = 0;
    assign status_captureWordCount = fifoIn_wordCount;
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
    `Sync(ctrl_fifoInDone, fifoIn_done, posedge, clk);
    
    reg[2:0] fifoIn_state = 0;
    always @(posedge img_dclk) begin
        fifoIn_rst <= 0; // Pulse
        fifoIn_lvPrev <= fifoIn_lv;
        fifoIn_header <= fifoIn_header<<16;
        fifoIn_headerCount <= fifoIn_headerCount-1;
        fifoIn_write_trigger <= 0; // Reset by default
        fifoIn_countStat <= 0; // Reset by default
        
        if (fifoIn_write_trigger) begin
            // Count the words in an image
            fifoIn_wordCount <= fifoIn_wordCount+1;
        end
        
        if (!fifoIn_lv) fifoIn_x <= 0;
        else            fifoIn_x <= fifoIn_x+1;
        
        if (!fifoIn_fv)                         fifoIn_y <= 0;
        else if (fifoIn_lvPrev && !fifoIn_lv)   fifoIn_y <= fifoIn_y+1;
        
        if (fifoIn_write_trigger) begin
            $display("[ImgController:fifoIn] Wrote word into FIFO: %x", fifoIn_write_data);
        end
        
        // Count pixel stats (number of highlights/shadows)
        // We're pipelining `fifoIn_countStat` and `fifoIn_countStatPx` here for performance
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
            fifoIn_wordCount <= 0;
            fifoIn_highlightCount <= 0;
            fifoIn_shadowCount <= 0;
            fifoIn_state <= 2;
        end
        
        // Delay state while FIFO resets
        2: begin
            fifoIn_state <= 3;
        end
        
        // Initiate writing header
        3: begin
            fifoIn_started <= !fifoIn_started;
            fifoIn_header <= cmd_header;
            fifoIn_headerCount <= HeaderWordCount-1;
            fifoIn_state <= 4;
        end
        
        // Write header
        4: begin
            $display("[ImgController:fifoIn] Header state: %0d", fifoIn_headerCount);
            fifoIn_write_trigger <= 1;
            fifoIn_write_data <= `LeftBits(fifoIn_header, 0, 16);
            if (!fifoIn_headerCount) begin
                fifoIn_state <= 5;
            end
        end
        
        // Wait for the frame to be invalid
        5: begin
            if (!fifoIn_fv) begin
                $display("[ImgController:fifoIn] Waiting for frame invalid...");
                fifoIn_state <= 6;
            end
        end
        
        // Wait for the frame to start
        6: begin
            if (fifoIn_fv) begin
                $display("[ImgController:fifoIn] Frame start");
                fifoIn_state <= 7;
            end
        end
        
        // Wait until the end of the frame
        7: begin
            fifoIn_countStat <= (fifoIn_lv && !fifoIn_x && !fifoIn_y);
            fifoIn_write_trigger <= fifoIn_lv;
            fifoIn_write_data <= {4'b0, img_d_reg};
            if (!fifoIn_fv) begin
                $display("[ImgController:fifoIn] Frame end");
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
    `TogglePulse(ctrl_cmdReadout, cmd_readout, posedge, clk);
    reg[`RegWidth(ImageSizeMax)-1:0] ctrl_readoutCount = 0;
    reg ctrl_fifoOutWrote = 0;
    reg ctrl_fifoOutDone = 0;
    
    localparam Ctrl_State_Idle          = 0; // +0
    localparam Ctrl_State_Capture       = 1; // +3
    localparam Ctrl_State_Readout       = 5; // +2
    localparam Ctrl_State_Count         = 8;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ramctrl_cmd <= `RAMController_Cmd_None;
        fifoOut_rst <= 0;
        ramctrl_write_trigger <= 0;
        
        ctrl_fifoOutWrote <= fifoOut_write_ready && fifoOut_write_trigger;
        if (ctrl_fifoOutWrote) begin
            $display("[ImgController] ctrl_readoutCount: %0d", ctrl_readoutCount);
            ctrl_readoutCount <= ctrl_readoutCount-1;
        end
        
        if (ctrl_readoutCount === 0) begin
            ctrl_fifoOutDone <= 1;
        end
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
        end
        
        Ctrl_State_Capture: begin
            $display("[IMGCTRL:Capture] Triggered");
            // Supply 'Write' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Write;
            $display("[IMGCTRL:Capture] Waiting for RAMController to be ready to write...");
            ctrl_state <= Ctrl_State_Capture+1;
        end
        
        Ctrl_State_Capture+1: begin
            // Wait for the write command to be consumed, and for the RAMController
            // to be ready to write.
            // This is necessary because the RAMController/SDRAM takes some time to
            // initialize upon power on. If we attempted a capture during this time,
            // we'd drop most/all of the pixels because RAMController/SDRAM wouldn't
            // be ready to write yet.
            if (ramctrl_cmd===`RAMController_Cmd_None && ramctrl_write_ready) begin
                $display("[IMGCTRL:Capture] Waiting for FIFO to reset...");
                // Start the FIFO data flow now that RAMController is ready to write
                ctrl_fifoInCaptureTrigger <= !ctrl_fifoInCaptureTrigger;
                ctrl_state <= Ctrl_State_Capture+2;
            end
        end
        
        Ctrl_State_Capture+2: begin
            // Wait for the fifoIn state machine to start
            if (ctrl_fifoInStarted) begin
                ctrl_state <= Ctrl_State_Capture+3;
            end
        end
        
        Ctrl_State_Capture+3: begin
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
                status_captureDone <= !status_captureDone;
                ctrl_state <= Ctrl_State_Idle;
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
            ctrl_readoutCount <= fifoIn_wordCount;
            ctrl_fifoOutDone <= 0;
            ctrl_state <= Ctrl_State_Readout+1;
        end
        
        Ctrl_State_Readout+1: begin
            // Wait for the read command and FIFO reset to be consumed
            if (ramctrl_cmd===`RAMController_Cmd_None && !fifoOut_rst) begin
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
        
        if (ctrl_cmdCapture) ctrl_state <= Ctrl_State_Capture;
        if (ctrl_cmdReadout) ctrl_state <= Ctrl_State_Readout;
    end
    
    // ====================
    // Connections
    // ====================
    // Connect input FIFO write -> pixel data
    // assign fifoIn_write_trigger = (fifoIn_headerWriteEn || fifoIn_pixelWrite);
    // assign fifoIn_write_data = (fifoIn_headerWriteEn ? `LeftBits(fifoIn_header, 0, 16) : {4'b0, img_d_reg});
    
    // Connect input FIFO read -> RAM write
    assign fifoIn_read_trigger = (!ramctrl_write_trigger || ramctrl_write_ready);
    
    // Connect RAM read -> output FIFO write
    assign fifoOut_write_trigger = ramctrl_read_ready;
    assign ramctrl_read_trigger = fifoOut_write_ready;
    assign fifoOut_write_data = ramctrl_read_data;
    
    // Connect output FIFO read -> readout port
    assign readout_ready = fifoOut_read_ready;
    assign fifoOut_read_trigger = readout_trigger;
    assign readout_data = fifoOut_read_data;
    
endmodule

`endif
