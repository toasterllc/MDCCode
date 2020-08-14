`include "../ClockGen.v"
`include "../MsgChannel.v"
`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    output reg[7:0]     led = 0 /* synthesis syn_keep=1 */
);
    // ====================
    // Clock PLL (24 MHz)
    // ====================
    wire a_clk;
    ClockGen #(
        .FREQ(24000000),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(5),
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
    
    reg a_a2b_trigger = 0;
    reg[7:0] a_a2b_msg = 0;
    wire b_a2b_trigger;
    wire[7:0] b_a2b_msg;
    MsgChannel channel_a2b(
        .in_clk(a_clk),
        .in_trigger(a_a2b_trigger),
        .in_msg(a_a2b_msg),
        .out_clk(b_clk),
        .out_trigger(b_a2b_trigger),
        .out_msg(b_a2b_msg)
    );
    
    reg b_b2a_trigger = 0;
    reg[7:0] b_b2a_msg = 0;
    wire a_b2a_trigger;
    wire[7:0] a_b2a_msg;
    MsgChannel channel_b2a(
        .in_clk(b_clk),
        .in_trigger(b_b2a_trigger),
        .in_msg(b_b2a_msg),
        .out_clk(a_clk),
        .out_trigger(a_b2a_trigger),
        .out_msg(a_b2a_msg)
    );
    
    reg a_state = 0;
    reg[7:0] a_num = 0;
    always @(posedge a_clk) begin
        case (a_state)
        0: begin
            a_a2b_trigger <= 1;
            a_a2b_msg <= a_num;
            a_state <= 1;
            
            `ifdef SIM
                $display("[A] sent: %0d", a_num);
            `endif
        end
        
        1: begin
            a_a2b_trigger <= 0;
            if (a_b2a_trigger) begin
                `ifdef SIM
                    $display("[A] received: %0d", a_b2a_msg);
                `endif
                a_num <= a_b2a_msg+1;
                a_state <= 0;
                
                led <= a_num;
            end
        end
        endcase
    end
    
    
    reg b_state = 0;
    reg[7:0] b_num = 0;
    always @(posedge b_clk) begin
        case (b_state)
        0: begin
            b_b2a_trigger <= 0;
            if (b_a2b_trigger) begin
                `ifdef SIM
                    $display("[B] received: %0d", b_a2b_msg);
                `endif
                b_num <= b_a2b_msg+1;
                b_state <= 1;
            end
        end
        
        1: begin
            b_b2a_trigger <= 1;
            b_b2a_msg <= b_num;
            b_state <= 0;
            `ifdef SIM
                $display("[B] sent: %0d", b_num);
            `endif
        end
        endcase
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
