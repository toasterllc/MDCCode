`timescale 1ns/1ps
`include "../AFIFO.v"
`include "../Icestick_AFIFOProducer/top.v"



`ifndef SIM


/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        12.000 MHz
 * Requested output frequency:   81.000 MHz
 * Achieved output frequency:    81.000 MHz
 */

module RCLKPLL(
    input  clock_in,
    output clock_out,
    output locked
    );

SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),        // DIVR =  0
        .DIVF(7'b0110101),    // DIVF = 53
        .DIVQ(3'b011),        // DIVQ =  3
        .FILTER_RANGE(3'b001)    // FILTER_RANGE = 1
    ) uut (
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .REFERENCECLK(clock_in),
        .PLLOUTCORE(clock_out)
        );

endmodule


`endif

module Iceboard_AFIFOConsumer(
    input wire clk12mhz,
    output wire led,
    
    input wire wclk,
    input wire w,
    input wire[11:0] wd
);

`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Iceboard_AFIFOConsumer);
        #1000000000;
        $finish;
    end
    
    // rclk
    reg rclk = 0;
    initial begin
        #7;
        forever begin
            rclk = !rclk;
            #30;
        end
    end
    
    Icestick_AFIFOProducer producer(.clk12mhz(clk12mhz), .wclk(wclk), .w(w), .wd(wd));
`else
    wire rclk;
    RCLKPLL pll(.clock_in(clk12mhz), .clock_out(rclk));
`endif
    
    // wire wclk;
    // assign wclk = rclk;
    
    reg r = 0;
    wire[11:0] rd;
    wire rempty;
    
    AFIFO afifo(
        .rclk(rclk),
        .r(r),
        .rd(rd),
        .rempty(rempty),
        
        .wclk(wclk),
        .w(w),
        .wd(wd),
        .wfull()
    );
    
    // Consume values
    reg[11:0] rval;
    reg rvalValid = 0;
    reg rfail = 0;
    always @(posedge rclk) begin
        if (!rfail) begin
            // Init
            if (!r) begin
                r <= 1;
            
            // Read if data is available
            end else if (!rempty) begin
                $display("Read value: %h", rd);
                rval <= rd;
                rvalValid <= 1;
                
                // Check if the current value is the previous value +1
                // `assert(!rvalValid | ((rval+1'b1)==rd));
                if (rvalValid & ((rval+1'b1)!=rd)) begin
                    $display("Error: read invalid value; wanted: %h got: %h", (rval+1'b1), rd);
                    rfail <= 1;
                    // Stop reading
                    r <= 0;
                end
            end
        end
    end
    
    assign led = rfail;
endmodule
