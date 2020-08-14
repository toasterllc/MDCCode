`include "../ClockGen.v"
`include "../MsgChannel.v"
`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0 /* synthesis syn_keep=1 */
);
    // ====================
    // Clock PLL (81 MHz)
    // ====================
    wire a_clk;
    ClockGen #(
        .FREQ(81000000),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) acg(.clk12mhz(clk12mhz), .clk(a_clk));
    
    // ====================
    // Clock PLL (96 MHz)
    // ====================
    wire b_clk;
    ClockGen #(
        .FREQ(96000000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) bcg(.clk12mhz(clk12mhz), .clk(b_clk));
    
    reg a_trigger = 0;
    reg[7:0] a_msg = 0;
    wire b_trigger;
    wire[7:0] b_msg;
    MsgChannel ca(
        .in_clk(a_clk),
        .in_trigger(a_trigger),
        .in_msg(a_msg),
        .out_clk(b_clk),
        .out_trigger(b_trigger),
        .out_msg(b_msg)
    );
    
    reg[7:0] delay = 0;
    reg[7:0] num = 0;
    always @(posedge a_clk) begin
        a_trigger <= 0;
        num <= num+1;
        
        if (delay) delay <= delay-1;
        else begin
            a_trigger <= 1;
            a_msg <= num;
            delay <= 20;
        end
    end
    
    always @(posedge b_clk) begin
        if (b_trigger) begin
            led <= b_msg[7:4]^b_msg[3:0];
            `ifdef SIM
                $display("Got message: %0d", b_msg);
            `endif
        end
    end
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        #1000000;
        $finish;
    end
    
`endif
    
endmodule
