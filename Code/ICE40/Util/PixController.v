`ifndef PixController_v
`define PixController_v

`include "TogglePulse.v"
`include "ToggleAck.v"

module PixController #(
    parameter ClkFreq = 24_000_000,
    parameter ImageSize = 256*256,
    localparam CmdCapture = 1'b0,
    localparam CmdReadout = 1'b1
)(
    input wire          clk,
    
    // Command port
    input wire          cmd,
    input wire[2:0]     cmd_ramBlock,
    input wire          cmd_trigger, // Toggle
    output reg          cmd_done = 0, // Toggle
    
    // TODO: consider re-ordering: readout_data, readout_trigger, readout_ready
    // Readout port
    output wire         readout_ready,
    input wire          readout_trigger,
    output wire[15:0]   readout_data,
    
    // Pix port
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    
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
    // RAMController
    // ====================
    
    wire        ramctrl_cmd_ready;
    reg         ramctrl_cmd_trigger = 0;
    reg[2:0]    ramctrl_cmd_block = 0;
    reg         ramctrl_cmd_write = 0;
    wire        ramctrl_write_ready;
    reg         ramctrl_write_trigger = 0;
    reg[15:0]   ramctrl_write_data = 0;
    wire        ramctrl_read_ready;
    wire        ramctrl_read_trigger;
    wire[15:0]  ramctrl_read_data;
    
    RAMController #(
        .ClkFreq(ClkFreq),
        .BlockSize(ImageSize)
    ) RAMController (
        .clk(clk),
        
        .cmd_ready(ramctrl_cmd_ready),
        .cmd_trigger(ramctrl_cmd_trigger),
        .cmd_block(ramctrl_cmd_block),
        .cmd_write(ramctrl_cmd_write),
        
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
    // FIFO
    // ====================
    reg fifo_writeEn = 0;
    wire fifo_readTrigger;
    wire[15:0] fifo_readData;
    wire fifo_readReady;
    BankFIFO #(
        .W(16),
        .N(8)
    ) BankFIFO (
        .rst_(1'b1),
        
        .w_clk(pix_dclk),
        .w_ready(), // TODO: handle not being able to write by signalling an error somehow?
        .w_trigger(fifo_writeEn && pix_lv_reg),
        .w_data({4'b0, pix_d_reg}),
        
        .r_clk(clk),
        .r_ready(fifo_readReady),
        .r_trigger(fifo_readTrigger),
        .r_data(fifo_readData)
    );
    
    reg ctrl_fifoCaptureTrigger = 0;
    `ToggleAck(fifo_captureTrigger, fifo_captureTriggerAck, ctrl_fifoCaptureTrigger, posedge, pix_dclk);
    
    reg[1:0] fifo_state = 0;
    always @(posedge pix_dclk) begin
        case (fifo_state)
        // Wait to be triggered
        0: begin
            fifo_writeEn <= 0;
            if (fifo_captureTrigger) begin
                fifo_captureTriggerAck <= !fifo_captureTriggerAck;
                fifo_state <= 1;
            end
        end
        
        // Wait for the frame to be invalid
        1: begin
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Waiting for frame invalid...");
                fifo_state <= 2;
            end
        end
        
        // Wait for the frame to start
        2: begin
            if (pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame start");
                fifo_writeEn <= 1;
                fifo_state <= 3;
            end
        end
        
        // Wait until the end of the frame
        3: begin
            if (!pix_fv_reg) begin
                $display("[PIXCTRL:FIFO] Frame end");
                fifo_state <= 0;
            end
        end
        endcase
    end
    
    
    
    // ====================
    // State Machine
    // ====================
    `TogglePulse(ctrl_cmdTrigger, cmd_trigger, posedge, clk);
    
    assign fifo_readTrigger = (!ramctrl_write_trigger || ramctrl_write_ready);
    assign readout_ready = ramctrl_read_ready;
    assign ramctrl_read_trigger = readout_trigger;
    assign readout_data = ramctrl_read_data;
    
    localparam Ctrl_State_Idle      = 0; // +0
    localparam Ctrl_State_Capture   = 1; // +1
    localparam Ctrl_State_Readout   = 3; // +1
    localparam Ctrl_State_Count     = 5;
    reg[$clog2(Ctrl_State_Count)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ramctrl_cmd_trigger <= 0;
        ramctrl_write_trigger <= 0;
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
            if (ctrl_cmdTrigger) begin
                ctrl_state <= (cmd===CmdCapture ? Ctrl_State_Capture : Ctrl_State_Readout);
            end
            
            // TODO: handle FIFO data being available when we don't expect it
            if (fifo_readReady) begin
            end
        end
        
        // Wait for RAM to accept write command
        Ctrl_State_Capture: begin
            if (ramctrl_cmd_ready && ramctrl_cmd_trigger) begin
                $display("[PIXCTRL:Capture] Start");
                // Start the FIFO data flow
                ctrl_fifoCaptureTrigger <= !ctrl_fifoCaptureTrigger;
                ctrl_state <= Ctrl_State_Capture+1;
            end else begin
                // Configure RAM command
                ramctrl_cmd_block <= cmd_ramBlock;
                ramctrl_cmd_write <= 1;
                ramctrl_cmd_trigger <= 1; // Assert until the command is accepted
            end
        end
        
        // Copy data from FIFO->RAM
        Ctrl_State_Capture+1: begin
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
            if (ramctrl_cmd_ready) begin
                $display("[PIXCTRL:Capture] Finished");
                // Signal that we're done
                cmd_done <= !cmd_done;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        
        Ctrl_State_Readout: begin
            if (ramctrl_cmd_ready && ramctrl_cmd_trigger) begin
                $display("[PIXCTRL:Readout] Start");
                ctrl_state <= Ctrl_State_Readout+1;
            end else begin
                // Configure RAM command
                ramctrl_cmd_block <= cmd_ramBlock;
                ramctrl_cmd_write <= 0;
                ramctrl_cmd_trigger <= 1; // Assert until the command is accepted
            end
        end
        
        Ctrl_State_Readout+1: begin
            // We're finished when RAMController says we've read all the pixels.
            // (RAMController knows when it's read the entire block, and we
            // define RAMController's block size as the image size.)
            if (ramctrl_cmd_ready) begin
                $display("[PIXCTRL:Readout] Finished");
                // Signal that we're done
                cmd_done <= !cmd_done;
                ctrl_state <= Ctrl_State_Idle;
            end
        end
        endcase
    end
    
endmodule

`endif
