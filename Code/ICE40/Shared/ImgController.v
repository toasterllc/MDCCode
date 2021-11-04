`ifndef ImgController_v
`define ImgController_v

`include "RAMController.v"
`include "TogglePulse.v"
`include "AFIFO.v"
`include "FletcherChecksum.v"
`include "Sync.v"

module ImgController #(
    parameter ClkFreq                   = 24_000_000,
    parameter HeaderWordCount           = 8,
    parameter ImgWordCount              = 4096*4096, // Total image word count (header + pixels + checksum)
    localparam HeaderWidth              = HeaderWordCount*16
)(
    input wire          clk,
    
    // Command port (clock domain: `clk`)
    input wire          cmd_capture,    // Toggle signal
    input wire          cmd_readout,    // Toggle signal
    input wire[0:0]     cmd_ramBlock,   // Destination RAM block
    input wire[0:0]     cmd_skipCount,  // Number of image frames to skip
    input wire[HeaderWidth-1:0]
                        cmd_header,
    
    // Readout port (clock domain: `clk`)
    output reg          readout_rst = 0,
    output reg          readout_start = 0,  // Toggle signal
    output wire         readout_ready,
    input wire          readout_trigger,
    output wire[15:0]   readout_data,
    
    // Status port (clock domain: `clk`)
    output reg          status_captureDone = 0, // Toggle signal
    output wire[`RegWidth(ImgWordCount)-1:0]
                        status_captureWordCount,
    output wire[17:0]   status_captureHighlightCount,
    output wire[17:0]   status_captureShadowCount,
    
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
    // ====================
    // RAMController
    // ====================
    reg         ramctrl_cmd_block = 0;
    reg[1:0]    ramctrl_cmd = 0;
    wire        ramctrl_write_ready;
    wire        ramctrl_write_trigger;
    wire[15:0]  ramctrl_write_data;
    wire        ramctrl_read_ready;
    wire        ramctrl_read_trigger;
    wire[15:0]  ramctrl_read_data;
    
    RAMController #(
        .ClkFreq(ClkFreq),
        .BlockCount(2)
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
    wire fifoIn_w_clk;
    wire fifoIn_w_ready;
    reg fifoIn_w_trigger = 0;
    reg[15:0] fifoIn_w_data = 0;
    wire fifoIn_r_clk;
    wire fifoIn_r_ready;
    wire fifoIn_r_trigger;
    wire[15:0] fifoIn_r_data;
    
    AFIFO AFIFO_fifoIn(
        .rst_(!fifoIn_rst),
        
        .w_clk(fifoIn_w_clk),
        .w_ready(fifoIn_w_ready),
        .w_trigger(fifoIn_w_trigger),
        .w_data(fifoIn_w_data),
        
        .r_clk(clk),
        .r_ready(fifoIn_r_ready),
        .r_trigger(fifoIn_r_trigger),
        .r_data(fifoIn_r_data)
    );
    
    assign fifoIn_w_clk = img_dclk;
    assign fifoIn_r_clk = clk;
    
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
    // fifoIn Checksum
    // ====================
    wire        fifoIn_checksum_clk;
    reg         fifoIn_checksum_rst = 0;
    reg         fifoIn_checksum_en = 0;
    wire[15:0]  fifoIn_checksum_din;
    wire[31:0]  fifoIn_checksum_dout;
    reg[31:0]   fifoIn_checksum_shiftReg = 0;
    reg         fifoIn_checksum_done_ = 0;
    FletcherChecksum #(
        .Width(32)
    ) FletcherChecksum_fifoIn(
        .clk    (fifoIn_checksum_clk ),
        .rst    (fifoIn_checksum_rst ),
        .en     (fifoIn_checksum_en  ),
        .din    (fifoIn_checksum_din ),
        .dout   (fifoIn_checksum_dout)
    );
    assign fifoIn_checksum_clk  = img_dclk;
    // fifoIn_checksum_din: treat `fifoIn_w_data` values as little-endian when
    // calculating the checksum, to match host behavior
    assign fifoIn_checksum_din  = {fifoIn_w_data[7:0], fifoIn_w_data[15:8]};
    
    // ====================
    // Pixel input state machine
    // ====================
    reg[`RegWidth(HeaderWordCount-1)-1:0] fifoIn_headerCount = 0;
    reg[HeaderWidth-1:0] fifoIn_header = 0;
    
    reg ctrl_fifoInCaptureTrigger = 0;
    `TogglePulse(fifoIn_captureTrigger, ctrl_fifoInCaptureTrigger, posedge, img_dclk);
    
    reg fifoIn_started = 0;
    `TogglePulse(ctrl_fifoInStarted, fifoIn_started, posedge, clk);
    
    reg[`RegWidth(ImgWordCount)-1:0] fifoIn_wordCount = 0;
    reg[17:0] fifoIn_highlightCount = 0;
    reg[17:0] fifoIn_shadowCount = 0;
    assign status_captureWordCount = fifoIn_wordCount;
    assign status_captureHighlightCount = fifoIn_highlightCount;
    assign status_captureShadowCount = fifoIn_shadowCount;
    
    wire fifoIn_lv = img_lv_reg;
    wire fifoIn_fv = img_fv_reg;
    reg fifoIn_lvPrev = 0;
    reg fifoIn_fvPrev = 0;
    reg[1:0] fifoIn_x = 0;
    reg[1:0] fifoIn_y = 0;
    reg fifoIn_countStat = 0;
    reg[11:0] fifoIn_countStatPx = 0;
    reg fifoIn_frameStart = 0;
    reg[$size(cmd_skipCount)-1:0] fifoIn_skipCount = 0;
    
    reg fifoIn_done = 0;
    `Sync(ctrl_fifoInDone, fifoIn_done, posedge, clk);
    
    reg[2:0] fifoIn_state = 0;
    always @(posedge img_dclk) begin
        fifoIn_rst <= 0; // Pulse
        fifoIn_lvPrev <= fifoIn_lv;
        fifoIn_fvPrev <= fifoIn_fv;
        fifoIn_header <= fifoIn_header<<16;
        fifoIn_headerCount <= fifoIn_headerCount-1;
        fifoIn_w_trigger <= 0; // Pulse
        fifoIn_countStat <= 0; // Pulse
        fifoIn_checksum_rst <= 0; // Pulse
        fifoIn_checksum_en <= 0; // Pulse
        fifoIn_checksum_shiftReg <= fifoIn_checksum_shiftReg>>16;
        fifoIn_checksum_done_ <= 0; // Pulse
        
        if (fifoIn_w_trigger) begin
            // Count the words in an image
            fifoIn_wordCount <= fifoIn_wordCount+1;
        end
        
        if (!fifoIn_lv) fifoIn_x <= 0;
        else            fifoIn_x <= fifoIn_x+1;
        
        if (!fifoIn_fv)                         fifoIn_y <= 0;
        else if (fifoIn_lvPrev && !fifoIn_lv)   fifoIn_y <= fifoIn_y+1;
        
        fifoIn_frameStart <= (!fifoIn_fvPrev && fifoIn_fv);
        if (fifoIn_frameStart && fifoIn_skipCount) begin
            fifoIn_skipCount <= fifoIn_skipCount-1;
        end
        
        if (fifoIn_w_trigger) begin
            $display("[ImgController:fifoIn] Wrote word into FIFO: %x (checksum: %h)", fifoIn_w_data, fifoIn_checksum_dout);
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
            fifoIn_checksum_rst <= 1;
            fifoIn_skipCount <= cmd_skipCount;
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
            fifoIn_w_trigger <= 1;
            fifoIn_w_data <= `LeftBits(fifoIn_header, 0, 16);
            fifoIn_checksum_en <= 1;
            if (!fifoIn_headerCount) begin
                fifoIn_state <= 5;
            end
        end
        
        // Wait for the frame to start
        5: begin
            if (fifoIn_frameStart && !fifoIn_skipCount) begin
                $display("[ImgController:fifoIn] Frame start");
                fifoIn_state <= 6;
            end
        end
        
        // Wait until the end of the frame
        6: begin
            fifoIn_countStat <= (fifoIn_lv && !fifoIn_x && !fifoIn_y);
            fifoIn_w_trigger <= fifoIn_lv;
            fifoIn_w_data <= {{img_d_reg[7:0]}, {4'b0, img_d_reg[11:8]}}; // Little endian
            fifoIn_checksum_en <= fifoIn_lv;
            fifoIn_checksum_shiftReg <= fifoIn_checksum_dout;
            fifoIn_checksum_done_ <= 1;
            if (!fifoIn_fv) begin
                $display("[ImgController:fifoIn] Frame end");
                fifoIn_state <= 7;
            end
        end
        
        // Write checksum
        7: begin
            $display("[ImgController:fifoIn] Writing checksum %0d/2 (checksum: %h)", (fifoIn_checksum_done_ ? 1 : 2), fifoIn_checksum_dout);
            fifoIn_w_trigger <= 1;
            fifoIn_w_data <= {fifoIn_checksum_shiftReg[7:0], fifoIn_checksum_shiftReg[15:8]}; // Little endian
            if (!fifoIn_checksum_done_) begin
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
    reg[`RegWidth(ImgWordCount)-1:0] ctrl_readoutCount = 0;
    reg ctrl_readoutWrote = 0;
    reg ctrl_readoutDone = 0;
    
    localparam Ctrl_State_Idle          = 0; // +0
    localparam Ctrl_State_Capture       = 1; // +3
    localparam Ctrl_State_Readout       = 5; // +2
    localparam Ctrl_State_Count         = 8;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ramctrl_cmd <= `RAMController_Cmd_None;
        readout_rst <= 0; // Pulse
        
        ctrl_readoutWrote <= readout_ready && readout_trigger;
        if (ctrl_readoutWrote) begin
            $display("[ImgController] ctrl_readoutCount: %0d", ctrl_readoutCount);
            ctrl_readoutCount <= ctrl_readoutCount-1;
        end
        
        if (ctrl_readoutCount === 0) begin
            ctrl_readoutDone <= 1;
        end
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
        end
        
        Ctrl_State_Capture: begin
            $display("[ImgController:Capture] Triggered");
            // Supply 'Write' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Write;
            $display("[ImgController:Capture] Waiting for RAMController to be ready to write...");
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
                $display("[ImgController:Capture] Waiting for FIFO to reset...");
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
            if (ctrl_fifoInDone) begin
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
            readout_rst <= 1;
            // Reset readout state
            ctrl_readoutCount <= ImgWordCount;
            ctrl_readoutDone <= 0;
            ctrl_state <= Ctrl_State_Readout+1;
        end
        
        Ctrl_State_Readout+1: begin
            // Wait for readout_rst to complete
            if (!readout_rst) begin
                readout_start <= !readout_start;
                ctrl_state <= Ctrl_State_Readout+2;
            end
        end
        
        Ctrl_State_Readout+2: begin
            if (ctrl_readoutDone) begin
                $display("[ImgController:Readout] Stopping");
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
    // assign fifoIn_w_trigger = (fifoIn_headerWriteEn || fifoIn_pixelWrite);
    // assign fifoIn_w_data = (fifoIn_headerWriteEn ? `LeftBits(fifoIn_header, 0, 16) : {4'b0, img_d_reg});
    
    // Connect fifoIn -> RAM write
    assign fifoIn_r_trigger = ramctrl_write_ready;
    assign ramctrl_write_trigger = fifoIn_r_ready;
    assign ramctrl_write_data = fifoIn_r_data;
    
    // Connect RAM read -> readout
    assign readout_ready = ramctrl_read_ready;
    assign readout_data = ramctrl_read_data;
    assign ramctrl_read_trigger = readout_trigger;
    
endmodule

`endif
