`ifndef PixController_v
`define PixController_v

`include "ToggleAck.v"

module PixController #(
    parameter ClkFreq = 24_000_000,
    localparam CmdCapture = 1'b0,
    localparam CmdReadout = 1'b1
)(
    input wire          clk,
    
    // Command port
    input wire          cmd_trigger, // Toggle
    input wire[2:0]     cmd_ramBlock,
    input wire          cmd,
    output reg          cmd_done = 0, // Toggle
    
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
    parameter ImageSize = 2304*1296;
    
    wire        ramctrl_cmd_ready;
    reg         ramctrl_cmd_trigger = 0;
    reg[2:0]    ramctrl_cmd_block = 0;
    reg         ramctrl_cmd_write = 0;
    wire        ramctrl_data_ready;
    wire        ramctrl_data_trigger;
    reg[15:0]   ramctrl_data_write = 0;
    wire[15:0]  ramctrl_data_read;
    
    RAMController #(
        .ClkFreq(ClkFreq),
        .BlockSize(ImageSize)
    ) RAMController (
        .clk(clk),
        
        .cmd_ready(ramctrl_cmd_ready),
        .cmd_trigger(ramctrl_cmd_trigger),
        .cmd_block(ramctrl_cmd_block),
        .cmd_write(ramctrl_cmd_write),
        
        .data_ready(ramctrl_data_ready),
        .data_trigger(ramctrl_data_trigger),
        .data_write(ramctrl_data_write),
        .data_read(ramctrl_data_read),
        
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
        .w_clk(pix_dclk),
        .w_ready(), // TODO: handle not being able to write by signalling an error somehow?
        .w_trigger(fifo_writeEn && pix_lv_reg),
        .w_data({4'b0, pix_d_reg}),
        
        .r_clk(clk),
        .r_ready(fifo_readReady),
        .r_trigger(fifo_readTrigger),
        .r_data(fifo_readData),
        .r_bank()
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
                fifo_state <= 2;
            end
        end
        
        // Wait for the frame to start
        2: begin
            if (pix_fv_reg) begin
                fifo_writeEn <= 1;
                fifo_state <= 3;
            end
        end
        
        // Wait until the end of the frame
        3: begin
            if (!pix_fv_reg) begin
                fifo_state <= 0;
            end
        end
        endcase
    end
    
    
    
    // ====================
    // State Machine
    // ====================
    `ToggleAck(ctrl_cmdTrigger, ctrl_cmdTriggerAck, cmd_trigger, posedge, clk);
    
    // TODO: maybe we should separate read/write ports of RAMController to simplify our logic?
    
    reg ctrl_captureEn = 0;
    reg ctrl_readoutEn = 0;
    reg ctrl_ramReadTrigger = 0;
    assign ramctrl_data_trigger = (ctrl_readoutEn ? readout_trigger : ctrl_ramReadTrigger);
    assign fifo_readTrigger = (ctrl_captureEn && (!ctrl_ramReadTrigger || ramctrl_data_ready));
    
    assign readout_ready = (ctrl_readoutEn ? ramctrl_data_ready : 0);
    assign readout_data = ramctrl_data_read;
    
    localparam Ctrl_State_Idle      = 0; // +0
    localparam Ctrl_State_Capture   = 1; // +2
    localparam Ctrl_State_Readout   = 2; // +0
    localparam Ctrl_State_Count     = 3; // +0
    reg[$clog2(Ctrl_State_Count)-1:0] ctrl_state = 0;
    always @(posedge clk) begin
        ctrl_captureEn <= 0;
        ctrl_readoutEn <= 0;
        ramctrl_cmd_trigger <= 0;
        ctrl_ramReadTrigger <= 0;
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
            if (ctrl_cmdTrigger) begin
                ctrl_cmdTriggerAck <= !ctrl_cmdTriggerAck; // Ack command
                ctrl_state <= (cmd===CmdCapture ? Ctrl_State_Capture : Ctrl_State_Readout);
            end
            
            // TODO: handle FIFO data being available when we don't expect it
            if (fifo_readReady) begin
            end
        end
        
        Ctrl_State_Capture: begin
            // Start the FIFO data flow
            ctrl_fifoCaptureTrigger <= !ctrl_fifoCaptureTrigger;
            // Configure RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd_write <= 1;
            // Next state
            ctrl_state <= Ctrl_State_Capture+1;
        end
        
        // Wait for RAM to accept write command
        Ctrl_State_Capture+1: begin
            if (ramctrl_cmd_ready && ramctrl_cmd_trigger) begin
                ctrl_state <= Ctrl_State_Capture+2;
            end else begin
                ramctrl_cmd_trigger <= 1; // Assert until the command is accepted
            end
        end
        
        // Copy data from FIFO->RAM
        Ctrl_State_Capture+2: begin
            // Enable reading from FIFO
            ctrl_captureEn <= 1;
            
            // By default, prevent `ctrl_ramReadTrigger` from being reset
            ctrl_ramReadTrigger <= ctrl_ramReadTrigger;
            
            // Reset `ctrl_ramReadTrigger` if the data was consumed
            if (ramctrl_data_ready && ctrl_ramReadTrigger) begin
                ctrl_ramReadTrigger <= 0;
            end
            
            // Copy word from FIFO->RAM
            if (fifo_readReady && fifo_readTrigger) begin
                ramctrl_data_write <= fifo_readData;
                ctrl_ramReadTrigger <= 1;
            end
            
            // We're finished when RAMController says we've received all the pixels.
            // (RAMController knows when it's written the entire block, and we
            // define RAMController's block size as the image size.)
            if (ramctrl_cmd_ready) begin
                // Signal that we're done
                cmd_done <= !cmd_done;
                state <= Ctrl_State_Idle;
            end
        end
        
        Ctrl_State_Readout: begin
            // Configure RAM command
            ramctrl_cmd_block <= cmd_ramBlock;
            ramctrl_cmd_write <= 0;
            // Next state
            ctrl_state <= Ctrl_State_Readout+1;
        end
        
        Ctrl_State_Readout+1: begin
            if (ramctrl_cmd_ready && ramctrl_cmd_trigger) begin
                ctrl_state <= Ctrl_State_Readout+2;
            end else begin
                ramctrl_cmd_trigger <= 1; // Assert until the command is accepted
            end
        end
        
        Ctrl_State_Readout+2: begin
            ctrl_readoutEn <= 1;
            
            // We're finished when RAMController says we've read all the pixels.
            // (RAMController knows when it's read the entire block, and we
            // define RAMController's block size as the image size.)
            if (ramctrl_cmd_ready) begin
                // Signal that we're done
                cmd_done <= !cmd_done;
                state <= Ctrl_State_Idle;
            end
        end
        endcase
    end
    
endmodule

`endif
