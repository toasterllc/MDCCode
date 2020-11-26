`include "Util.v"
`include "ClockGen.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"

`timescale 1ps/1ps

`ifdef SIM
localparam ImageWidth = 2304;
localparam ImageHeight = 2;
// localparam ImageWidth = 16;
// localparam ImageHeight = 16;
`else
localparam ImageWidth = 2304;
localparam ImageHeight = 1296;
`endif

localparam ImageSize = ImageWidth*ImageHeight;

module Top(
    input wire          clk24mhz,
    input wire          pix_dclk,
    output reg[3:0]     led = 0
);
    // ====================
    // Clock (120 MHz)
    // ====================
    localparam ClkFreq = 120_000_000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(39),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen(.clkRef(clk24mhz), .clk(clk));
    
    reg[`RegWidth(ImageWidth-1)-1:0] ix = 0;
    reg[`RegWidth(ImageHeight-1)-1:0] iy = 0;
    reg[2:0] state = 0;
    reg[3:0] counter = 0;
    reg pix_fv_reg = 0;
    reg pix_lv_reg = 0;
    always @(posedge pix_dclk) begin
        pix_fv_reg <= 0;
        pix_lv_reg <= 0;
        counter <= counter+1;
        
        case (state)
        0: begin
            ix <= 0;
            iy <= 0;
            if (&counter) begin
                counter <= 0;
                state <= 1;
            end
        end
        
        1: begin
            pix_fv_reg <= 1;
            if (&counter) begin
                state <= 2;
            end
        end
        
        2: begin
            pix_fv_reg <= 1;
            
            if (ix !== ImageWidth-1) begin
                pix_lv_reg <= 1;
            
            end else begin
                counter <= 0;
                state <= 3;
            end
            
            if (pix_lv_reg) begin
                ix <= ix+1;
            end
        end
        
        3: begin
            pix_fv_reg <= 1;
            if (&counter) begin
                if (iy !== ImageHeight-1) begin
                    ix <= 0;
                    iy <= iy+1;
                    state <= 2;
                
                end else begin
                    counter <= 0;
                    state <= 0;
                end
            end
        end
        endcase
    end
    
    
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
        .w_trigger(fifo_writeEn && pix_lv_reg),
        .w_data({4'b0, ix}),
        
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
    
    localparam Ctrl_State_Idle      = 0; // +0
    localparam Ctrl_State_Capture   = 1; // +4
    localparam Ctrl_State_Count     = 6;
    reg[`RegWidth(Ctrl_State_Count-1)-1:0] ctrl_state = 0;
    reg[`RegWidth(ImageSize-1)-1:0] ctrl_pixelCounter = 0;
    reg[3:0] ctrl_counter = 0;
    always @(posedge clk) begin
        ctrl_counter <= ctrl_counter+1;
        fifo_readTrigger <= 0;
        
        case (ctrl_state)
        Ctrl_State_Idle: begin
        end
        
        Ctrl_State_Capture: begin
            $display("[CTRL] Triggered");
            led[0] <= !led[0];
            ctrl_state <= Ctrl_State_Capture+1;
        end
        
        Ctrl_State_Capture+1: begin
            // Start the FIFO data flow
            ctrl_fifoCaptureTrigger <= !ctrl_fifoCaptureTrigger;
            ctrl_state <= Ctrl_State_Capture+2;
        end
        
        Ctrl_State_Capture+2: begin
            // Wait until the FIFO is reset
            // This is necessary so that when we observe `fifo_readReady`,
            // we know it's from the start of this session, not from a previous one.
            if (ctrl_fifoRstDone) begin
                $display("[CTRL] Receiving data from FIFO...");
                ctrl_pixelCounter <= ImageSize-1;
                ctrl_state <= Ctrl_State_Capture+3;
            end
        end
        
        // Receive data out of FIFO
        Ctrl_State_Capture+3: begin
            fifo_readTrigger <= 1;
            
            if (fifo_readTrigger && fifo_readReady) begin
                $display("[CTRL] Got pixel: %0d (%0d)", fifo_readData, ctrl_pixelCounter);
                ctrl_pixelCounter <= ctrl_pixelCounter-1;
                if (!ctrl_pixelCounter) begin
                    ctrl_state <= Ctrl_State_Capture+4;
                end
            end
        end
        
        // Wait for extra pixels that we don't expect
        Ctrl_State_Capture+4: begin
            if (&ctrl_counter) begin
                if (fifo_readReady) begin
                    // We got a pixel we didn't expect
                    $display("[CTRL] Got extra pixel ❌");
                    led[3] <= !led[3];
                    `Finish;
                end
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
    
    reg pix_dclk = 0;
    
    Top Top(.*);
    
    initial forever begin
        #5102; // 98 MHz
        pix_dclk = !pix_dclk;
    end
    
    // initial begin
    //     $dumpfile("Top.vcd");
    //     $dumpvars(0, Testbench);
    // end
endmodule
`endif
