`ifndef PixController_v
`define PixController_v

`include "RAMController.v"
`include "TogglePulse.v"
`include "AFIFO.v"
`include "Delay.v"

`define PixController_Cmd_None      2'b00
`define PixController_Cmd_Capture   2'b01
`define PixController_Cmd_Readout   2'b10
`define PixController_Cmd_Stop      2'b11

module PixController #(
    parameter ClkFreq = 24_000_000,
    parameter ImageSize = 256*256
)(
    input wire          clk,
    
    // Command port (clock domain: `clk`)
    input wire[1:0]     cmd,
    input wire[2:0]     cmd_ramBlock,
    
    // Capture port
    output reg          capture_done = 0,
    output wire         capture_pixelDropped,
    output reg[39:0]    capture_status = 0, // TODO: remove
    
    // Readout port (clock domain: `clk`)
    output wire         readout_ready,
    input wire          readout_trigger,
    output wire[15:0]   readout_data,
    output wire         readout_done,
    
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
    
    wire pix_dclk_int;
    Delay #(
        .Count(1)
    ) Delay (
        .in(pix_dclk),
        .out(pix_dclk_int)
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
            .INPUT_CLK(pix_dclk_int),
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
        .INPUT_CLK(pix_dclk_int),
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
        .INPUT_CLK(pix_dclk_int),
        .PACKAGE_PIN(pix_lv),
        .D_IN_0(pix_lv_reg)
    );
    
    // ====================
    // FIFO
    // ====================
    reg fifo_rst = 0;
    wire fifo_rst_done;
    reg fifo_writeEn = 0;
    wire fifo_writeReady;
    wire fifo_readTrigger;
    wire[15:0] fifo_readData;
    wire fifo_readReady;
    AFIFO #(
        .W(16),
        .N(8)
    ) AFIFO (
        .rst(fifo_rst),
        .rst_done(fifo_rst_done),
        
        .w_clk(pix_dclk_int),
        .w_ready(fifo_writeReady), // TODO: handle not being able to write by signalling an error somehow?
        .w_trigger(fifo_writeEn && pix_lv_reg),
        .w_data({4'b0, pix_d_reg}),
        
        .r_clk(clk),
        .r_ready(fifo_readReady),
        .r_trigger(fifo_readTrigger),
        .r_data(fifo_readData)
    );
    
    reg ctrl_fifoCaptureTrigger = 0;
    `TogglePulse(fifo_captureTrigger, ctrl_fifoCaptureTrigger, posedge, pix_dclk_int);
    `TogglePulse(fifo_rstDone, fifo_rst_done, posedge, pix_dclk_int);
    `TogglePulse(ctrl_fifoRstDone, fifo_rst_done, posedge, clk);
    
    reg fifo_pixelDropped = 0;
    reg[2:0] fifo_state = 0;
    always @(posedge pix_dclk_int) begin
        fifo_writeEn <= 0; // Reset by default
        
        case (fifo_state)
        // Idle: wait to be triggered
        0: begin
        end
        
        // Reset FIFO / ourself
        1: begin
            fifo_rst <= !fifo_rst;
            fifo_pixelDropped <= 0;
            capture_status[31:0] <= 0;
            fifo_state <= 2;
        end
        
        // Wait for FIFO to be done resetting
        2: begin
            if (fifo_rstDone) begin
                fifo_state <= 3;
            end
        end
        
        // Wait for the frame to be invalid
        3: begin
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Waiting for frame invalid...");
                fifo_state <= 4;
            end
        end
        
        // Wait for the frame to start
        4: begin
            if (pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame start");
                fifo_state <= 5;
            end
        end
        
        // Wait until the end of the frame
        5: begin
            fifo_writeEn <= 1;
            
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame end");
                fifo_state <= 0;
            end
        end
        endcase
        
        if (fifo_captureTrigger) begin
            fifo_state <= 1;
        end
        
        // Watch for dropped pixels
        if (fifo_writeEn && pix_lv_reg && !fifo_writeReady) begin
            fifo_pixelDropped <= 1;
            capture_status[31:0] <= capture_status+1;
            $display("[PIXCTRL:FIFO] Pixel dropped ❌");
            `Finish;
        end
        
        capture_status[39:32] <= fifo_state;
        
        // if (fifo_writeEn && pix_lv_reg && fifo_writeReady) begin
        //     capture_status <= capture_status+1;
        // end
        
        // if (fifo_writeEn && pix_lv_reg) begin
        //     capture_status <= capture_status+1;
        // end
        
        // if (!pix_fv_reg && pix_lv_reg) begin
        //     capture_status <= 32'hAABBCCDD;
        // end
    end
    
    
    
    // ====================
    // State Machine
    // ====================
    assign fifo_readTrigger = (!ramctrl_write_trigger || ramctrl_write_ready);
    assign readout_ready = ramctrl_read_ready;
    assign ramctrl_read_trigger = readout_trigger;
    assign readout_data = ramctrl_read_data;
    assign readout_done = ramctrl_read_done;
    
    `Sync(capture_pixelDroppedSync, fifo_pixelDropped, posedge, clk);
    assign capture_pixelDropped = capture_pixelDroppedSync;
    
    localparam Ctrl_State_Idle      = 0; // +0
    localparam Ctrl_State_Capture   = 1; // +3
    localparam Ctrl_State_Readout   = 5; // +0
    localparam Ctrl_State_Stop      = 6; // +0
    localparam Ctrl_State_Count     = 7;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ramctrl_cmd <= `RAMController_Cmd_None;
        ramctrl_write_trigger <= 0;
        capture_done <= 0;
        
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
            // Wait for RAMController to be ready to write.
            // This is necessary because the RAMController/SDRAM takes some time to
            // initialize upon power on. If we attempted a capture during this time,
            // we'd drop most/all of the pixels because RAMController/SDRAM wouldn't
            // be ready to write yet.
            if (ramctrl_write_ready) begin
                // Start the FIFO data flow now that RAMController is ready to write
                ctrl_fifoCaptureTrigger <= !ctrl_fifoCaptureTrigger;
                ctrl_state <= Ctrl_State_Capture+2;
            end
        end
        
        Ctrl_State_Capture+2: begin
            // Wait until the FIFO is reset
            // This is necessary so that when we observe `fifo_readReady`,
            // we know it's from the start of this session, not from a previous one.
            if (ctrl_fifoRstDone) begin
                ctrl_state <= Ctrl_State_Capture+3;
            end
        end
        
        // Copy data from FIFO->RAM
        Ctrl_State_Capture+3: begin
            // By default, prevent `ramctrl_write_trigger` from being reset
            ramctrl_write_trigger <= ramctrl_write_trigger;
            
            // Reset `ramctrl_write_trigger` if RAMController accepted the data
            if (ramctrl_write_ready && ramctrl_write_trigger) begin
                ramctrl_write_trigger <= 0;
            end
            
            // Copy word from FIFO->RAM
            if (fifo_readReady && fifo_readTrigger) begin
                $display("[PIXCTRL:Capture] Got pixel");
                ramctrl_write_data <= fifo_readData;
                ramctrl_write_trigger <= 1;
            end
            
            // We're finished when RAMController says we've received all the pixels.
            // (RAMController knows when it's written the entire block, and we
            // define RAMController's block size as the image size.)
            if (ramctrl_write_done) begin
                $display("[PIXCTRL:Capture] Finished");
                capture_done <= 1;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        
        Ctrl_State_Readout: begin
            $display("[PIXCTRL:Readout] Triggered");
            // Supply 'Read' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Read;
            ctrl_state <= Ctrl_State_Idle;
        end
        
        Ctrl_State_Stop: begin
            $display("[PIXCTRL:Stop] Triggered");
            // Supply 'Stop' RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd <= `RAMController_Cmd_Stop;
            ctrl_state <= Ctrl_State_Idle;
        end
        endcase
        
        if (cmd !== `PixController_Cmd_None) begin
            case (cmd)
            `PixController_Cmd_Capture:     ctrl_state <= Ctrl_State_Capture;
            `PixController_Cmd_Readout:     ctrl_state <= Ctrl_State_Readout;
            `PixController_Cmd_Stop:        ctrl_state <= Ctrl_State_Stop;
            endcase
        end
    end
    
endmodule

`endif
