`include "Util.v"
`include "ClockGen.v"
`include "AFIFO.v"
`include "BankFIFO.v"
`timescale 1ns/1ps

module Top(
    input wire clk24mhz,
    output reg[3:0] led = 0
);
    // ====================
    // w_clk (100.5 MHz)
    // ====================
    wire w_clk;
    ClockGen #(
        .FREQ(100_000_000),
        .DIVR(1),
        .DIVF(66),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_w_clk(.clkRef(clk24mhz), .clk(w_clk));
    
    // ====================
    // r_clk (120 MHz)
    // ====================
    wire r_clk;
    ClockGen #(
        .FREQ(120_000_000),
        .DIVR(0),
        .DIVF(39),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_r_clk(.clkRef(clk24mhz), .clk(r_clk));
    
    // ====================
    // rstClk (50 MHz)
    // ====================
    wire rstClk;
    ClockGen #(
        .FREQ(50_000_000)
    ) ClockGen_rstClk(.clkRef(clk24mhz), .clk(rstClk));
    
    // ====================
    // BankFIFO
    // ====================
    reg w_trigger = 0;
    reg[15:0] w_data = 0;
    wire w_ready;
    
    reg r_trigger = 0;
    wire[15:0] r_data;
    wire r_ready;
    
    reg rst_ = 0;
    
    BankFIFO #(
        .W(16),
        .N(8)
    ) BankFIFO (
        .rst_(rst_),
        
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ready(w_ready),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ready(r_ready)
    );
    
    
    reg[7:0] w_counter = 0;
    reg[7:0] w_delay = 0;
    reg w_init = 0;
    always @(posedge w_clk) begin
        if (!w_init) begin
            w_trigger <= 1;
            w_init <= 1;
        end
        
        if (w_ready && w_trigger) begin
            $display("Wrote %x", w_data);
            w_counter <= w_counter+1;
            if (w_counter === 255) begin
                w_trigger <= 0;
                w_delay <= 2;
            end
        end
        
        if (w_delay) begin
            w_delay <= w_delay-1;
            if (w_delay === 1) begin
                w_trigger <= 1;
                w_data <= w_data+1;
            end
        end
    end
    
    // ====================
    // Reader
    // ====================
    reg[15:0] r_lastData = 0;
    reg r_init = 0;
    reg[7:0] r_counter = 0;
    always @(posedge r_clk) begin
        if (!r_init) begin
            r_trigger <= 1;
            r_init <= 1;
        end
        
        if (r_ready && r_trigger) begin
            $display("Read data (0x%x): %x", BankFIFO.r_addr, r_data);
            r_lastData <= r_data;
            if (r_data < r_lastData) begin
                $display("BAD DATA (r_lastData:%x, r_data:%x)", r_lastData, r_data);
                `Finish;
            end
        end
        
        if (BankFIFO.r_addr===8'hBD) begin
            r_trigger <= 0;
            r_counter <= 18;
        end
        
        if (r_counter) begin
            r_counter <= r_counter-1;
            if (r_counter === 1) begin
                r_trigger <= 1;
            end
        end
    end
    
    
    reg[7:0] rstCounter = 0;
    always @(posedge rstClk) begin
        rstCounter <= rstCounter+1;
        rst_ <= !(&rstCounter);
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


