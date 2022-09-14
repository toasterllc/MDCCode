`include "Util.v"
`include "ClockGen.v"
`include "Sync.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`timescale 1ns/1ps

module Top(
    input wire ice_stm_spi_clk,
    input wire ice_img_clk16mhz,
    output reg[3:0] ice_led = 0
);
    // ====================
    // w_clk (48 MHz)
    // ====================
    wire w_clk;
    ClockGen #(
        .FREQOUT(48_000_000),
        .DIVR(0),
        .DIVF(47),
        .DIVQ(4),
        .FILTER_RANGE(1)
    ) ClockGen_w_clk(.clkRef(ice_img_clk16mhz), .clk(w_clk));
    
    
    // // ====================
    // // r_clk (24 MHz)
    // // ====================
    // wire r_clk;
    // ClockGen #(
    //     .FREQOUT(24_000_000),
    //     .DIVR(0),
    //     .DIVF(47),
    //     .DIVQ(5),
    //     .FILTER_RANGE(1)
    // ) ClockGen_r_clk(.clkRef(ice_img_clk16mhz), .clk(r_clk));
    
    // // ====================
    // // r_clk (48 MHz)
    // // ====================
    // wire r_clk;
    // ClockGen #(
    //     .FREQOUT(48_000_000),
    //     .DIVR(0),
    //     .DIVF(47),
    //     .DIVQ(4),
    //     .FILTER_RANGE(1)
    // ) ClockGen_r_clk(.clkRef(ice_img_clk16mhz), .clk(r_clk));
    
    // ====================
    // r_clk (96 MHz)
    // ====================
    wire r_clk;
    ClockGen #(
        .FREQOUT(96_000_000),
        .DIVR(0),
        .DIVF(47),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_r_clk(.clkRef(ice_img_clk16mhz), .clk(r_clk));
    
    
    // ====================
    // Init Delay: wait for RAMs to be operational
    // See ICE40-RAMInvalidDataNotes.txt
    // ====================
    reg initDelay_done = 0;
    `Sync(w_initDelayDone, initDelay_done, posedge, w_clk);
    
    reg[4:0] initDelay_counter = 0;
    always @(posedge ice_stm_spi_clk) begin
        initDelay_counter <= initDelay_counter+1;
        if (&initDelay_counter) begin
            initDelay_done <= 1;
        end
    end
    
    
    
    
    reg rstFIFO_req = 0;
    reg[7:0] rstFIFO_counter = 0;
    always @(posedge w_clk) begin
        rstFIFO_counter <= rstFIFO_counter+1;
        if (&rstFIFO_counter) begin
            $display("[Async] Reset FIFO");
            rstFIFO_req <= !rstFIFO_req;
        end
    end
    
    // ====================
    // AFIFO
    // ====================
    localparam W = 16;
    
    reg w_trigger = 0;
    reg[W-1:0] w_data = 0;
    wire w_ready;
    
    reg r_trigger = 0;
    wire[W-1:0] r_data;
    wire r_ready;
    
    reg fifo_rst_ = 0;
    
    AFIFO #(
        .W(W)
    ) AFIFO (
        .rst_(fifo_rst_),
        
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ready(w_ready),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ready(r_ready)
    );
    
    // ====================
    // Writer
    // ====================
    reg r_rstReady = 0;
    `ToggleAck(w_rrstReady, w_rrstReadyAck, r_rstReady, posedge, w_clk);
    `TogglePulse(w_rstFIFOReq, rstFIFO_req, posedge, w_clk);
    
    reg w_fifoRstDone = 0;
    reg[1:0] w_state = 0;
    always @(posedge w_clk) begin
        fifo_rst_ <= 1;
        
        if (!w_initDelayDone) begin
            $display("Waiting to start...");
        
        end else begin
            ice_led[0] <= 1'b1;
            w_trigger <= 0;
            
            case (w_state)
            0: begin
                w_trigger <= 1;
                if (w_ready && w_trigger) begin
                    $display("[Write] %x @ 0x%x", w_data, AFIFO.w_baddr);
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
                $display("[Write] Reset FIFO");
                // Reset FIFO
                fifo_rst_ <= 0;
                w_state <= 3;
            end
            
            3: begin
                // Delay state to wait for the reset to complete
                w_fifoRstDone <= !w_fifoRstDone;
                w_state <= 0;
            end
            endcase
            
            if (w_rstFIFOReq) begin
                w_trigger <= 0;
                w_state <= 1;
            end
        end
    end
    
    // ====================
    // Reader
    // ====================
    reg[W-1:0] r_lastData = 0;
    reg r_lastDataInit = 0;
    reg r_init = 0;
    reg[7:0] r_counter = 0;
    
    `TogglePulse(r_rstFIFOReq, rstFIFO_req, posedge, r_clk);
    `TogglePulse(r_wfifoRstDone, w_fifoRstDone, posedge, r_clk);
    
    reg[1:0] r_state = 0;
    always @(posedge r_clk) begin
        r_trigger <= 0;
        
        case (r_state)
        0: begin
            r_trigger <= 1;
            if (r_ready && r_trigger) begin
                $display("[Read] %x @ 0x%x", r_data, AFIFO.r_baddr);
                r_lastData <= r_data;
                if (r_lastDataInit && r_data!==(r_lastData+1'b1)) begin
                    ice_led[3:1] <= ~0;
                    $display("BAD DATA (r_lastData:%x, r_data:%x)", r_lastData, r_data);
                    `Finish;
                end else begin
                    // ice_led <= ~ice_led;
                end
                r_lastDataInit <= 1;
            end
        end
        
        1: begin
            $display("[Read] Reset FIFO");
            // Signal that we're ready for the reset
            r_rstReady <= !r_rstReady;
            r_state <= 2;
        end
        
        2: begin
            // Wait for reset to complete
            if (r_wfifoRstDone) begin
                r_lastDataInit <= 0;
                r_state <= 0;
            end
        end
        endcase
        
        if (r_rstFIFOReq) begin
            r_trigger <= 0;
            r_state <= 1;
        end
    end
endmodule








`ifdef SIM
module Testbench();
    reg ice_stm_spi_clk = 0;
    reg ice_img_clk16mhz = 0;
    wire[3:0] ice_led;
    Top Top(.*);
    
    initial forever #10 ice_stm_spi_clk = !ice_stm_spi_clk;
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
endmodule
`endif


