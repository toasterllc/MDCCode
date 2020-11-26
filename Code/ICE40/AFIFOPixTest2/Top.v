`include "Util.v"
`include "ClockGen.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`include "PixSim.v"
`timescale 1ns/1ps

localparam ImageWidth = 2304;
localparam ImageHeight = 1296;

module Top(
    input wire clk24mhz,
    
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    
    output reg[3:0]     led = 0
);
    // localparam ImageWidth = 16;
    // localparam ImageHeight = 16;
    localparam PixelCount = ImageWidth*ImageHeight;
    
    // ====================
    // Clock (99 MHz)
    // ====================
    wire clk;
    ClockGen #(
        .FREQ(99_000_000),
        .DIVR(0),
        .DIVF(32),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen(.clkRef(clk24mhz), .clk(clk));
    
    // ====================
    // FIFO
    // ====================
    reg fifo_rst = 0;
    wire fifo_rst_done;
    reg fifo_writeEn = 0;
    wire fifo_writeReady;
    reg fifo_readTrigger = 0;
    wire[15:0] fifo_readData;
    wire fifo_readReady;
    AFIFO #(
        .W(16),
        .N(8)
    ) AFIFO (
        .rst(fifo_rst),
        .rst_done(fifo_rst_done),
        
        .w_clk(pix_dclk),
        .w_ready(fifo_writeReady), // TODO: handle not being able to write by signalling an error somehow?
        .w_trigger(fifo_writeEn && pix_lv),
        .w_data({4'b0, pix_d}),
        
        .r_clk(clk),
        .r_ready(fifo_readReady),
        .r_trigger(fifo_readTrigger),
        .r_data(fifo_readData)
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
            fifo_rst <= !fifo_rst;
            fifo_state <= 2;
        end
        
        // Wait for FIFO to be done resetting
        2: begin
            if (fifo_rstDone) begin
                $display("[FIFO] Waiting for frame invalid...");
                fifo_state <= 3;
            end
        end
        
        // Wait for the frame to be invalid
        3: begin
            if (!pix_fv) begin
                fifo_state <= 4;
            end
        end
        
        // Wait for the frame to start
        4: begin
            if (pix_fv) begin
                $display("[FIFO] Frame start");
                fifo_state <= 5;
            end
        end
        
        // Wait until the end of the frame
        5: begin
            fifo_writeEn <= 1;
            
            if (!pix_fv) begin
                $display("[FIFO] Frame end");
                fifo_state <= 0;
            end
        end
        endcase
        
        if (fifo_captureTrigger) begin
            fifo_state <= 1;
        end
        
        // Watch for dropped pixels
        if (fifo_writeEn && pix_lv && !fifo_writeReady) begin
            $display("[FIFO] Pixel dropped ❌");
            led <= 4'b1111;
            `Finish;
        end
    end
    
    
    
    
    
    
    
    // ====================
    // Control State Machine
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
    
    reg[1:0] ctrl_state = 0;
    reg[`RegWidth(PixelCount-1)-1:0] ctrl_counter = 0;
    always @(posedge clk) begin
        fifo_readTrigger <= 0;
        
        case (ctrl_state)
        0: begin
            ctrl_counter <= 0;
        end
        
        1: begin
            // Start the FIFO data flow
            $display("[CTRL] Triggering FIFO data flow...");
            ctrl_fifoCaptureTrigger <= !ctrl_fifoCaptureTrigger;
            ctrl_state <= 2;
        end
        
        2: begin
            // Wait until the FIFO is reset
            // This is necessary so that when we observe `fifo_readReady`,
            // we know it's from the start of this session, not from a previous one.
            if (ctrl_fifoRstDone) begin
                $display("[CTRL] Observed FIFO reset");
                ctrl_state <= 3;
            end
        end
        
        3: begin
            fifo_readTrigger <= 1;
            if (fifo_readReady && fifo_readTrigger) begin
                $display("[CTRL] Got pixel: %0d", ctrl_counter);
                ctrl_counter <= ctrl_counter+1;
            end
            
            if (ctrl_counter === PixelCount-1) begin
                $display("[CTRL] Finished");
                ctrl_state <= 0;
            end
        end
        endcase
        
        if (ctrl_state===0 && ctrl_captureTrigger) begin
            $display("[CTRL] Capture trigger");
            ctrl_state <= 1;
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
    
    Top Top(.*);
    
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


