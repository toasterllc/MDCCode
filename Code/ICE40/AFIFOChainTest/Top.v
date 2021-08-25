`include "Util.v"
`include "ClockGen.v"
`include "Sync.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`timescale 1ns/1ps

`define Width 16
`define Count 8

module AFIFOChain #(
    parameter W = 16,
    parameter N = 2
)(
    input wire rst_,
    input wire clk, // Propagation clock; use the faster of `w_clk` and `r_clk`
    
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire w_ready,
    output wire w_ready_half, // Whether half of the FIFO can be written
    
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire r_ready,
    output wire r_ready_half // Whether half of the FIFO can be read
);
    wire[N-1:0]        afifo_rst_;
    wire[N-1:0]        afifo_w_clk;
    wire[N-1:0]        afifo_w_trigger;
    wire[N*W-1:0]      afifo_w_data;
    wire[N-1:0]        afifo_w_ready;
    wire[N-1:0]        afifo_r_clk;
    wire[N-1:0]        afifo_r_trigger;
    wire[N*W-1:0]      afifo_r_data;
    wire[N-1:0]        afifo_r_ready;
    
    genvar i;
    for (i=0; i<N; i=i+1) begin
        AFIFO #(
            .W(W)
        ) AFIFO (
            .rst_(afifo_rst_[i]),
        
            .w_clk(afifo_w_clk[i]),
            .w_trigger(afifo_w_trigger[i]),
            .w_data(afifo_w_data[i*W +: W]),
            .w_ready(afifo_w_ready[i]),
        
            .r_clk(afifo_r_clk[i]),
            .r_trigger(afifo_r_trigger[i]),
            .r_data(afifo_r_data[i*W +: W]),
            .r_ready(afifo_r_ready[i])
        );
        
        assign afifo_rst_[i]            = rst_;
        
        if (i == 0)
        assign afifo_w_clk[i]           = w_clk;
        else
        assign afifo_w_clk[i]           = clk; // Propagation clock
        
        if (i == 0)
        assign afifo_w_trigger[i]       = w_trigger;
        else
        assign afifo_w_trigger[i]       = afifo_r_ready[i-1];
        
        if (i == 0)
        assign afifo_w_data[i*W +: W]   = w_data;
        else
        assign afifo_w_data[i*W +: W]   = afifo_r_data[(i-1)*W +: W];
        
        if (i < N-1)
        assign afifo_r_trigger[i]       = afifo_w_ready[i+1];
        else
        assign afifo_r_trigger[i]       = r_trigger;
        
        if (i < N-1)
        assign afifo_r_clk[i]           = clk; // Propagation clock
        else
        assign afifo_r_clk[i]           = r_clk;
    end
    
    assign w_ready                      = afifo_w_ready[0];
    assign r_data                       = afifo_r_data[(N-1)*W +: W];
    assign r_ready                      = afifo_r_ready[N-1];
    
    // w_ready_half: whether left half of the FIFO can be written
    // == whether the middle-left AFIFO is empty
    // == middle-left AFIFO's !r_ready
    wire r_leftEmpty                    = !afifo_r_ready[(N/2)-1];
    `Sync(w_rLeftEmpty, r_leftEmpty, posedge, w_clk);
    assign w_ready_half                 = w_rLeftEmpty;
    
    // r_ready_half: whether right half of the FIFO can be read
    // == whether the middle-right AFIFO is full
    // == middle-right AFIFO's !w_ready
    wire w_rightFull                    = !afifo_w_ready[N/2];
    `Sync(r_wRightFull, w_rightFull, posedge, r_clk);
    assign r_ready_half                 = r_wRightFull;
    
    // wire        afifo1_rst_;
    // wire        afifo1_w_clk;
    // wire        afifo1_w_trigger;
    // wire[W-1:0] afifo1_w_data;
    // wire        afifo1_w_ready;
    // wire        afifo1_r_clk;
    // wire        afifo1_r_trigger;
    // wire[W-1:0] afifo1_r_data;
    // wire        afifo1_r_ready;
    //
    // wire        afifo2_rst_;
    // wire        afifo2_w_clk;
    // wire        afifo2_w_trigger;
    // wire[W-1:0] afifo2_w_data;
    // wire        afifo2_w_ready;
    // wire        afifo2_r_clk;
    // wire        afifo2_r_trigger;
    // wire[W-1:0] afifo2_r_data;
    // wire        afifo2_r_ready;
    //
    // assign afifo1_rst_          = rst_;
    // assign afifo1_w_clk         = w_clk;
    // assign afifo1_w_trigger     = w_trigger;
    // assign afifo1_w_data        = w_data;
    // assign w_ready              = afifo1_w_ready;
    // assign afifo1_r_clk         = w_clk;
    // assign afifo1_r_trigger     = afifo2_w_ready;
    //
    // assign afifo2_rst_          = rst_;
    // assign afifo2_w_clk         = w_clk;
    // assign afifo2_w_trigger     = afifo1_r_ready;
    // assign afifo2_w_data        = afifo1_r_data;
    // assign afifo2_r_clk         = r_clk;
    // assign afifo2_r_trigger     = r_trigger;
    // assign r_data               = afifo2_r_data;
    // assign r_ready              = afifo2_r_ready;
    //
    // AFIFO #(
    //     .W(W)
    // ) AFIFO1 (
    //     .rst_(afifo1_rst_),
    //
    //     .w_clk(afifo1_w_clk),
    //     .w_trigger(afifo1_w_trigger),
    //     .w_data(afifo1_w_data),
    //     .w_ready(afifo1_w_ready),
    //
    //     .r_clk(afifo1_r_clk),
    //     .r_trigger(afifo1_r_trigger),
    //     .r_data(afifo1_r_data),
    //     .r_ready(afifo1_r_ready)
    // );
    //
    // AFIFO #(
    //     .W(W)
    // ) AFIFO2 (
    //     .rst_(afifo2_rst_),
    //
    //     .w_clk(afifo2_w_clk),
    //     .w_trigger(afifo2_w_trigger),
    //     .w_data(afifo2_w_data),
    //     .w_ready(afifo2_w_ready),
    //
    //     .r_clk(afifo2_r_clk),
    //     .r_trigger(afifo2_r_trigger),
    //     .r_data(afifo2_r_data),
    //     .r_ready(afifo2_r_ready)
    // );

endmodule

module Top #(
    parameter W = `Width,
    parameter N = `Count
)(
    input wire rst_,
    input wire clk,
    
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire w_ready,
    output wire w_ready_half, // Whether half of the FIFO can be written
    
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire r_ready,
    output wire r_ready_half // Whether half of the FIFO can be read
);
    AFIFOChain #(
        .W(W),
        .N(N)
    ) AFIFOChain(
        .rst_(rst_),
        .clk(clk),
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ready(w_ready),
        .w_ready_half(w_ready_half),
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ready(r_ready),
        .r_ready_half(r_ready_half)
    );
endmodule

`ifdef SIM
module Testbench();
    localparam W = `Width;
    localparam N = `Count;
    
    reg rst_ = 1;
    wire clk;
    reg w_clk = 0;
    reg w_trigger = 1;
    reg[W-1:0] w_data = 0;
    wire w_ready;
    wire w_ready_half;
    reg r_clk = 0;
    reg r_trigger = 0;
    wire[W-1:0] r_data;
    wire r_ready;
    wire r_ready_half;
    
    Top #(
        .W(W),
        .N(N)
    ) Top(
        .rst_(rst_),
        .clk(clk),
        .w_clk(w_clk),
        .w_trigger(w_trigger),
        .w_data(w_data),
        .w_ready(w_ready),
        .w_ready_half(w_ready_half),
        .r_clk(r_clk),
        .r_trigger(r_trigger),
        .r_data(r_data),
        .r_ready(r_ready),
        .r_ready_half(r_ready_half)
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

            if (r_ready_half) begin
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
