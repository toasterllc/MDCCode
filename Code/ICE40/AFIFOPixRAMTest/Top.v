`include "Util.v"
`include "ClockGen.v"
`include "AFIFO.v"
// `include "BankFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"

`ifdef SIM
`include "PixSim.v"
`include "../../mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

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
    
    // // ====================
    // // Clock (114 MHz)
    // // ====================
    // localparam ClkFreq = 114_000_000;
    // wire clk;
    // ClockGen #(
    //     .FREQ(ClkFreq),
    //     .DIVR(0),
    //     .DIVF(37),
    //     .DIVQ(3),
    //     .FILTER_RANGE(2)
    // ) ClockGen(.clkRef(clk24mhz), .clk(clk));
    
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
        .w_data({4'b0, pix_d_reg}),
        
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
                
                ctrl_state <= Ctrl_State_Idle;
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
