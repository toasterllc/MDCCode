`include "Util.v"
`include "ClockGen.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`include "RAMController.v"

`ifdef SIM
`include "PixSim.v"
`include "../../mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

`ifdef SIM
// localparam ImageWidth = 2304;
// localparam ImageHeight = 1296;
localparam ImageWidth = 16;
localparam ImageHeight = 16;
`else
localparam ImageWidth = 2304;
localparam ImageHeight = 1296;
`endif

localparam ImageSize = ImageWidth*ImageHeight;

module Top(
    input wire clk24mhz,
    
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
    inout wire[15:0]    ram_dq,
    
    output reg[3:0]     led = 0
);
    // localparam ImageWidth = 16;
    // localparam ImageHeight = 16;
    localparam PixelCount = ImageWidth*ImageHeight;
    
    // // ====================
    // // Clock (102 MHz)
    // // ====================
    // localparam ClkFreq = 102_000_000;
    // wire clk;
    // ClockGen #(
    //     .FREQ(ClkFreq),
    //     .DIVR(0),
    //     .DIVF(33),
    //     .DIVQ(3),
    //     .FILTER_RANGE(2)
    // ) ClockGen(.clkRef(clk24mhz), .clk(clk));
    
    // ====================
    // Clock (114 MHz)
    // ====================
    localparam ClkFreq = 114_000_000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(37),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen(.clkRef(clk24mhz), .clk(clk));
    
    // ====================
    // RAMController
    // ====================
    
    reg[2:0]    ramctrl_cmd_block = 0;
    reg[1:0]    ramctrl_cmd = 0;
    wire        ramctrl_write_ready;
    reg         ramctrl_write_trigger = 0;
    reg[15:0]   ramctrl_write_data = 0;
    wire        ramctrl_write_done;
    
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
        
        .read_ready(),
        .read_trigger(1'b0),
        .read_data(),
        .read_done(),
        
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
    reg fifo_rst = 0;
    wire fifo_rst_done;
    reg fifo_writeEn = 0;
    wire fifo_writeReady;
    wire fifo_readTrigger;
    wire[15:0] fifo_readData;
    wire fifo_readReady;
    AFIFO #(
        .Width(16),
        .Size(256)
    ) AFIFO (
        // .rst(fifo_rst),
        // .rst_done(fifo_rst_done),
        
        .wclk(pix_dclk),
        .wok(fifo_writeReady), // TODO: handle not being able to write by signalling an error somehow?
        .wtrigger(fifo_writeEn && pix_lv_reg),
        .wdata({4'b0, pix_d_reg}),
        
        .rclk(clk),
        .rok(fifo_readReady),
        .rtrigger(fifo_readTrigger),
        .rdata(fifo_readData)
    );
    
    reg ctrl_fifoCaptureTrigger = 0;
    `TogglePulse(fifo_captureTrigger, ctrl_fifoCaptureTrigger, posedge, pix_dclk);
    `TogglePulse(fifo_rstDone, fifo_rst_done, posedge, pix_dclk);
    `TogglePulse(ctrl_fifoRstDone, fifo_rst_done, posedge, clk);
    
    reg[2:0] fifo_state = 0;
    always @(posedge pix_dclk) begin
        fifo_writeEn <= 0; // Reset by default
        
        case (fifo_state)
        // Idle: wait to be triggered
        0: begin
        end
        
        // Reset FIFO / ourself
        1: begin
            // fifo_rst <= !fifo_rst;
            fifo_state <= 2;
        end
        
        // Wait for FIFO to be done resetting
        2: begin
            if (1'b1) begin
                $display("[FIFO] Waiting for frame invalid...");
                fifo_state <= 3;
            end
        end
        
        // Wait for the frame to be invalid
        3: begin
            if (!pix_fv_reg) begin
                fifo_state <= 4;
            end
        end
        
        // Wait for the frame to start
        4: begin
            if (pix_fv_reg) begin
                $display("[FIFO] Frame start");
                fifo_state <= 5;
            end
        end
        
        // Wait until the end of the frame
        5: begin
            fifo_writeEn <= 1;
            
            if (!pix_fv_reg) begin
                $display("[FIFO] Frame end");
                fifo_state <= 0;
            end
        end
        endcase
        
        if (fifo_captureTrigger) begin
            fifo_state <= 1;
        end
        
        // Watch for dropped pixels
        if (fifo_writeEn && pix_lv_reg && !fifo_writeReady) begin
            $display("[FIFO] Pixel dropped ❌");
            led[2] <= 1;
            `Finish;
        end
    end
    
    
    
    // ====================
    // State Machine
    // ====================
    reg ctrl_captureTrigger = 0;
    reg[9:0] ctrl_captureTriggerCounter = 0;    
    always @(posedge clk) begin
        ctrl_captureTrigger <= 0;
        ctrl_captureTriggerCounter <= ctrl_captureTriggerCounter+1;
        if (&ctrl_captureTriggerCounter) begin
            ctrl_captureTrigger <= 1;
        end
    end
    
    assign fifo_readTrigger = (!ramctrl_write_trigger || ramctrl_write_ready);
    
    localparam Ctrl_State_Idle      = 0; // +0
    localparam Ctrl_State_Capture   = 1; // +4
    localparam Ctrl_State_Count     = 6;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    reg[3:0] ctrl_counter = 0;
    always @(posedge clk) begin
        ramctrl_cmd <= `RAMController_Cmd_None;
        ramctrl_write_trigger <= 0;
        ctrl_counter <= ctrl_counter+1;
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
        end
        
        Ctrl_State_Capture: begin
            $display("[CTRL] Triggered");
            led[0] <= !led[0];
            // Supply 'Write' RAM command
            ramctrl_cmd_block <= 0;
            ramctrl_cmd <= `RAMController_Cmd_Write;
            $display("[CTRL] Waiting for RAMController to be ready to write...");
            ctrl_state <= Ctrl_State_Capture+1;
        end
        
        Ctrl_State_Capture+1: begin
            // Wait for RAMController to be ready to write.
            // This is necessary because the RAMController/SDRAM takes some time to
            // initialize upon power on. If we attempted a capture during this time,
            // we'd drop most/all of the pixels because RAMController/SDRAM wouldn't
            // be ready to write yet.
            if (ramctrl_write_ready) begin
                $display("[CTRL] Waiting for FIFO to reset...");
                // Start the FIFO data flow now that RAMController is ready to write
                ctrl_fifoCaptureTrigger <= !ctrl_fifoCaptureTrigger;
                ctrl_state <= Ctrl_State_Capture+2;
            end
        end
        
        Ctrl_State_Capture+2: begin
            // Wait until the FIFO is reset
            // This is necessary so that when we observe `fifo_readReady`,
            // we know it's from the start of this session, not from a previous one.
            if (1'b1) begin
                $display("[CTRL] Receiving data from FIFO...");
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
                $display("[CTRL] Got pixel: %0d", fifo_readData);
                ramctrl_write_data <= fifo_readData;
                ramctrl_write_trigger <= 1;
            end
            
            // We're finished when RAMController says we've received all the pixels.
            // (RAMController knows when it's written the entire block, and we
            // define RAMController's block size as the image size.)
            if (ramctrl_write_done) begin
                $display("[CTRL] Finished");
                ctrl_counter <= 0;
                ctrl_state <= Ctrl_State_Capture+4;
            end
        end
        
        // Wait for extra pixels that we don't expect
        Ctrl_State_Capture+4: begin
            if (&ctrl_counter) begin
                ctrl_state <= Ctrl_State_Idle;
            end
            
            if (fifo_readReady) begin
                // We got a pixel we didn't expect
                $display("[CTRL] Got extra pixel ❌");
                led[3] <= 1;
            end
        end
        endcase
        
        if (ctrl_state===Ctrl_State_Idle && ctrl_captureTrigger) begin
            ctrl_state <= Ctrl_State_Capture;
        end
    end
endmodule








`ifdef SIM
module Testbench();
    reg clk24mhz = 0;
    wire[3:0] led;
    
    wire        pix_dclk;
    wire[11:0]  pix_d;
    wire        pix_fv;
    wire        pix_lv;
    wire        pix_rst_;
    wire        pix_sclk;
    tri1        pix_sdata;
    
    wire        ram_clk;
    wire        ram_cke;
    wire[1:0]   ram_ba;
    wire[12:0]  ram_a;
    wire        ram_cs_;
    wire        ram_ras_;
    wire        ram_cas_;
    wire        ram_we_;
    wire[1:0]   ram_dqm;
    wire[15:0]  ram_dq;
    
    Top Top(.*);
    
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
    
    PixSim #(
        .ImageWidth(ImageWidth),
        .ImageHeight(ImageHeight)
    ) PixSim (
        .pix_dclk(pix_dclk),
        .pix_d(pix_d),
        .pix_fv(pix_fv),
        .pix_lv(pix_lv),
        .pix_rst_(pix_rst_)
    );
    
    // initial begin
    //     $dumpfile("Top.vcd");
    //     $dumpvars(0, Testbench);
    // end
endmodule
`endif
