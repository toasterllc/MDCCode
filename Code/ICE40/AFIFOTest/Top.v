`include "Util.v"
`include "ClockGen.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output reg[3:0] led = 0
);
    // // ====================
    // // w_clk (156 MHz)
    // // ====================
    // wire w_clk;
    // ClockGen #(
    //     .FREQ(156_000_000),
    //     .DIVR(0),
    //     .DIVF(25),
    //     .DIVQ(2),
    //     .FILTER_RANGE(2)
    // ) ClockGen_w_clk(.clkRef(clk24mhz), .clk(w_clk));
    //
    // // ====================
    // // r_clk (96 MHz)
    // // ====================
    // wire r_clk;
    // ClockGen #(
    //     .FREQ(96_000_000),
    //     .DIVR(0),
    //     .DIVF(31),
    //     .DIVQ(3),
    //     .FILTER_RANGE(2)
    // ) ClockGen_r_clk(.clkRef(clk24mhz), .clk(r_clk));
    
    
    
    
    
    
    // ====================
    // w_clk (48 MHz)
    // ====================
    wire w_clk;
    ClockGen #(
        .FREQ(48_000_000),
        .DIVR(0),
        .DIVF(31),
        .DIVQ(4),
        .FILTER_RANGE(2)
    ) ClockGen_w_clk(.clkRef(clk24mhz), .clk(w_clk));
    
    // ====================
    // r_clk (96 MHz)
    // ====================
    wire r_clk;
    ClockGen #(
        .FREQ(96_000_000),
        .DIVR(0),
        .DIVF(31),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_r_clk(.clkRef(clk24mhz), .clk(r_clk));
    
    
    
    
    
    
    reg rst_req = 0;
    reg[7:0] rst_counter = 0;
    always @(posedge w_clk) begin
        rst_counter <= rst_counter+1;
        if (&rst_counter) begin
            $display("RESET");
            rst_req <= !rst_req;
        end
    end
    
    // ====================
    // AFIFO
    // ====================
    reg w_trigger = 0;
    reg[15:0] w_data = 0;
    wire w_ready;
    
    reg r_trigger = 0;
    wire[15:0] r_data;
    wire r_ready;
    
    reg fifo_rst = 0;
    wire fifo_rst_done;
    
    AFIFO #(
        .W(16),
        .N(8)
    ) AFIFO (
        .rst(fifo_rst),
        .rst_done(fifo_rst_done),
        
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ready(w_ready),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ready(r_ready)
    );
    
    reg r_rstReady = 0;
    `ToggleAck(w_rrstReady, w_rrstReadyAck, r_rstReady, posedge, r_clk);
    
    `TogglePulse(w_rstReq, rst_req, posedge, w_clk);
    `TogglePulse(w_fifoRstDone, fifo_rst_done, posedge, w_clk);
    
    reg[1:0] w_state = 0;
    always @(posedge w_clk) begin
        w_trigger <= 0;
        
        case (w_state)
        0: begin
            w_trigger <= 1;
            if (w_ready && w_trigger) begin
                $display("Write %x @ 0x%x", w_data, AFIFO.w_baddr);
                w_data <= w_data+1;
            end
        end
        
        1: begin
            // Wait for read domain to signal that they're ready for the reset
            if (w_rrstReady) begin
                w_rrstReadyAck <= !w_rrstReadyAck;
                w_state <= 2;
            end
        end
        
        2: begin
            // Reset FIFO
            fifo_rst <= !fifo_rst;
            w_state <= 3;
        end
        
        3: begin
            // Wait for reset to complete
            if (w_fifoRstDone) begin
                w_state <= 0;
            end
        end
        endcase
        
        if (w_rstReq) begin
            w_trigger <= 0;
            w_state <= 1;
        end
    end
    
    // ====================
    // Reader
    // ====================
    reg[15:0] r_lastData = 0;
    reg r_lastDataInit = 0;
    reg r_init = 0;
    reg[7:0] r_counter = 0;
    
    `TogglePulse(r_rstReq, rst_req, posedge, r_clk);
    `TogglePulse(r_fifoRstDone, fifo_rst_done, posedge, r_clk);
    
    reg[1:0] r_state = 0;
    always @(posedge r_clk) begin
        r_trigger <= 0;
        
        case (r_state)
        0: begin
            r_trigger <= 1;
            if (r_ready && r_trigger) begin
                $display("Read %x @ 0x%x", r_data, AFIFO.r_baddr);
                r_lastData <= r_data;
                if (r_lastDataInit && r_data!==(r_lastData+1'b1)) begin
                    $display("BAD DATA (r_lastData:%x, r_data:%x)", r_lastData, r_data);
                    led <= 4'b1111;
                    `Finish;
                end
                r_lastDataInit <= 1;
            end
        end
        
        1: begin
            // Signal that we're ready for the reset
            r_rstReady <= !r_rstReady;
            r_state <= 2;
        end
        
        2: begin
            // Wait for reset to complete
            if (r_fifoRstDone) begin
                r_lastDataInit <= 0;
                r_state <= 0;
            end
        end
        endcase
        
        if (r_rstReq) begin
            r_trigger <= 0;
            r_state <= 1;
        end
    end
endmodule








`ifdef SIM
module Testbench();
    reg clk24mhz = 0;
    wire[3:0] led;
    Top Top(
        .clk24mhz(clk24mhz),
        .led(led)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Testbench);
    end
endmodule
`endif


