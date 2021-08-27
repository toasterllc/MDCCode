`include "Util.v"
`include "ClockGen.v"
`include "Sync.v"
`include "AFIFOChain.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`timescale 1ns/1ps

`define Width 8
`define Count 8

module Top #(
    parameter W = `Width,
    parameter N = `Count
)(
    input wire rst_,
    
    output wire prop_w_ready, // Whether half of the FIFO can be written
    output wire prop_r_ready, // Whether half of the FIFO can be read
    
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire w_ready,
    
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire r_ready
);
    AFIFOChain #(
        .W(W),
        .N(N)
    ) AFIFOChain(
        .rst_(rst_),
        
        .prop_clk(w_clk),
        .prop_w_ready(prop_w_ready),
        .prop_r_ready(prop_r_ready),
        
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ready(w_ready),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ready(r_ready)
    );
endmodule

`ifdef SIM
module Testbench();
    localparam W = `Width;
    localparam N = `Count;
    
    reg rst_ = 1;
    wire prop_w_ready;
    wire prop_r_ready;
    reg w_clk = 0;
    reg w_trigger = 1;
    reg[W-1:0] w_data = 0;
    wire w_ready;
    reg r_clk = 0;
    reg r_trigger = 0;
    wire[W-1:0] r_data;
    wire r_ready;
    
    Top #(
        .W(W),
        .N(N)
    ) Top(
        .rst_(rst_),
        
        .prop_w_ready(prop_w_ready),
        .prop_r_ready(prop_r_ready),
        
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ready(w_ready),
        
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ready(r_ready)
    );
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Testbench);
    end
    
    // w_clk > r_clk
    initial forever #10 w_clk = !w_clk;
    initial forever #15 r_clk = !r_clk;
    assign clk = w_clk; // AFIFOChain requires `clk` to be the faster of w_clk and r_clk
    
    // // w_clk < r_clk
    // initial forever #10 w_clk = !w_clk;
    // initial forever #5 r_clk = !r_clk;
    // assign clk = r_clk; // AFIFOChain requires `clk` to be the faster of w_clk and r_clk
    
    initial begin
        forever begin
            wait(!w_clk);
            wait(w_clk);
            if (w_trigger && w_ready) begin
                #2;
                if (w_data == 'd1023) begin
                    w_trigger = 0;
                end
                $display("Wrote %0d", w_data);
                w_data = w_data+1;
            end
        end
    end
    
    initial begin
        forever begin
            wait(!r_clk);
            wait(r_clk);
            
            if (prop_r_ready) begin
                #1;
                r_trigger = 1;
                
                forever begin
                    wait(!r_clk);

                    if (!r_ready) begin
                        $display("NO DATA TO READ");
                        $finish;
                    end
                    
                    $display("Read: %0d", r_data);
                    wait(r_clk);
                end
            end
        end
    end
    
endmodule
`endif
