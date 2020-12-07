`ifndef PixController_v
`define PixController_v

`include "RAMController.v"
`include "TogglePulse.v"
`include "AFIFO.v"

`define PixController_Cmd_None      2'b00
`define PixController_Cmd_Capture   2'b01
`define PixController_Cmd_Readout   2'b10

module PixController #(
    parameter ClkFreq = 24_000_000,
    parameter ImageSize = 256*256
)(
    input wire          clk,
    
    // Command port (clock domain: `clk`)
    input wire[1:0]     cmd,
    input wire[2:0]     cmd_ramBlock,
    
    // Readout port (clock domain: `readout_clk`)
    input wire          readout_clk,
    output wire         readout_ready,
    input wire          readout_trigger,
    output wire[15:0]   readout_data,
    
    // Status port (clock domain: `clk`)
    output reg          status_captureDone = 0,
    output wire         status_capturePixelDropped,
    output reg          status_readoutStarted = 0,
    
    // Pix port (clock domain: `pix_dclk`)
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    
    // RAM port (clock domain: `ram_clk`)
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
    // RAMController
    // ====================
    reg[2:0]    ramctrl_cmd_block = 0;
    reg[1:0]    ramctrl_cmd = 0;
    wire        ramctrl_write_ready;
    reg         ramctrl_write_trigger = 0;
    reg[15:0]   ramctrl_write_data = 0;
    wire        ramctrl_write_done;
    wire        ramctrl_read_ready;
    wire        ramctrl_read_trigger;
    wire[15:0]  ramctrl_read_data;
    wire        ramctrl_read_done;
    
    RAMController #(
        .ClkFreq(ClkFreq),
        .BlockSize(ImageSize)
    ) RAMController (
        .clk(clk),
        
        .cmd_block(ramctrl_cmd_block),
        .cmd(ramctrl_cmd),
        
        .write_ready(ramctrl_write_ready),
        .write_trigger(ramctrl_write_trigger),
        .write_data(ramctrl_write_data),
        .write_done(ramctrl_write_done),
        
        .read_ready(ramctrl_read_ready),
        .read_trigger(ramctrl_read_trigger),
        .read_data(ramctrl_read_data),
        .read_done(ramctrl_read_done),
        
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
        
        .w_clk(pix_dclk),
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
    // Pin: pix_d
    // ====================
    genvar i;
    wire[11:0] pix_d_reg;
    for (i=0; i<12; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b0000_00)
        ) SB_IO_pix_d (
            .INPUT_CLK(pix_dclk),
            .PACKAGE_PIN(pix_d[i]),
            .D_IN_0(pix_d_reg[i])
        );
    end
    
    // ====================
    // Pin: pix_fv
    // ====================
    wire pix_fv_reg;
    SB_IO #(
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_pix_fv (
        .INPUT_CLK(pix_dclk),
        .PACKAGE_PIN(pix_fv),
        .D_IN_0(pix_fv_reg)
    );
    
    // ====================
    // Pin: pix_lv
    // ====================
    wire pix_lv_reg;
    SB_IO #(
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_pix_lv (
        .INPUT_CLK(pix_dclk),
        .PACKAGE_PIN(pix_lv),
        .D_IN_0(pix_lv_reg)
    );
    
    // ====================
    // Pixel input state machine
    // ====================
    reg fifoIn_writeEn = 0;
    
    reg ctrl_fifoInCaptureTrigger = 0;
    `TogglePulse(fifoIn_captureTrigger, ctrl_fifoInCaptureTrigger, posedge, pix_dclk);
    
    reg fifoIn_started = 0;
    `TogglePulse(ctrl_fifoInStarted, fifoIn_started, posedge, clk);
    
    reg fifoIn_pixelDropped = 0;
    reg[2:0] fifoIn_state = 0;
    always @(posedge pix_dclk) begin
        fifoIn_rst <= 0; // Pulse
        fifoIn_writeEn <= 0; // Reset by default
        
        case (fifoIn_state)
        // Idle: wait to be triggered
        0: begin
        end
        
        // Reset FIFO / ourself
        1: begin
            fifoIn_rst <= 1;
            fifoIn_pixelDropped <= 0;
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
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Waiting for frame invalid...");
                fifoIn_state <= 4;
            end
        end
        
        // Wait for the frame to start
        4: begin
            if (pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame start");
                fifoIn_state <= 5;
            end
        end
        
        // Wait until the end of the frame
        5: begin
            fifoIn_writeEn <= 1;
            
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame end");
                fifoIn_state <= 0;
            end
        end
        endcase
        
        if (fifoIn_captureTrigger) begin
            fifoIn_state <= 1;
        end
        
        // Watch for dropped pixels
        if (fifoIn_write_trigger && !fifoIn_write_ready) begin
            fifoIn_pixelDropped <= 1;
            $display("[PIXCTRL:FIFO] Pixel dropped ❌");
            `Finish;
        end
    end
    
    // ====================
    // Control State Machine
    // ====================
    `Sync(status_capturePixelDroppedSync, fifoIn_pixelDropped, posedge, clk);
    assign status_capturePixelDropped = status_capturePixelDroppedSync;
    
    localparam Ctrl_State_Idle      = 0; // +0
    localparam Ctrl_State_Capture   = 1; // +3
    localparam Ctrl_State_Readout   = 5; // +1
    localparam Ctrl_State_Count     = 7;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ramctrl_cmd <= `RAMController_Cmd_None;
        fifoOut_rst <= 0;
        status_captureDone <= 0;
        status_readoutStarted <= 0;
        ramctrl_write_trigger <= 0;
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
        end
        
        Ctrl_State_Capture: begin
            $display("[PIXCTRL:Capture] Triggered");
            // Supply 'Write' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Write;
            $display("[PIXCTRL:Capture] Waiting for RAMController to be ready to write...");
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
                $display("[PIXCTRL:Capture] Waiting for FIFO to reset...");
                // Start the FIFO data flow now that RAMController is ready to write
                ctrl_fifoInCaptureTrigger <= !ctrl_fifoInCaptureTrigger;
                ctrl_state <= Ctrl_State_Capture+2;
            end
        end
        
        Ctrl_State_Capture+2: begin
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
                // $display("[PIXCTRL:Capture] Got pixel: %0d", fifoIn_read_data);
                ramctrl_write_data <= fifoIn_read_data;
                ramctrl_write_trigger <= 1;
            end
            
            // We're finished when RAMController says we've received all the pixels.
            // (RAMController knows when it's written the entire block, and we
            // define RAMController's block size as the image size.)
            if (ramctrl_write_done) begin
                $display("[PIXCTRL:Capture] Finished");
                status_captureDone <= 1;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        
        Ctrl_State_Readout: begin
            $display("[PIXCTRL:Readout] Triggered");
            // Supply 'Read' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Read;
            // Reset output FIFO
            fifoOut_rst <= 1;
            ctrl_state <= Ctrl_State_Readout+1;
        end
        
        Ctrl_State_Readout+1: begin
            // Wait for the read command and FIFO reset to be consumed
            if (ramctrl_cmd===`RAMController_Cmd_None && !fifoOut_rst) begin
                status_readoutStarted <= 1;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        endcase
        
        if (cmd !== `PixController_Cmd_None) begin
            case (cmd)
            `PixController_Cmd_Capture:     ctrl_state <= Ctrl_State_Capture;
            `PixController_Cmd_Readout:     ctrl_state <= Ctrl_State_Readout;
            endcase
        end
    end
    
    // ====================
    // Connections
    // ====================
    // Connect input FIFO write -> pixel data
    assign fifoIn_write_trigger = fifoIn_writeEn && pix_lv_reg;
    assign fifoIn_write_data = {4'b0, pix_d_reg};
    
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
