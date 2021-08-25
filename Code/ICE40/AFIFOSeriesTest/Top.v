`include "Util.v"
`include "ClockGen.v"
`include "Sync.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`timescale 1ns/1ps

`define Width 16
`define Count 8

module AFIFOSeries #(
    parameter W = 16,
    parameter N = 2
)(
    input wire rst_,
    
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire w_ready,
    
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire r_ready
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
        assign afifo_w_clk[i]           = w_clk;
        
        if (i == 0)
        assign afifo_w_trigger[i]       = w_trigger;
        else
        assign afifo_w_trigger[i]       = afifo_r_ready[i-1];
        
        if (i == 0)
        assign afifo_w_data[i*W +: W]   = w_data;
        else
        assign afifo_w_data[i*W +: W]   = afifo_r_data[(i-1)*W +: W];
        
        if (i == 0)
        assign w_ready                  = afifo_w_ready[i];
        else
        assign afifo_r_trigger[i-1]     = afifo_w_ready[i];
        
        if (i < N-1)
        assign afifo_r_clk[i]           = w_clk;
        else
        assign afifo_r_clk[i]           = r_clk;
        
        if (i == N-1)
        assign afifo_r_trigger[i]       = r_trigger;
        
        if (i == N-1)
        assign r_data                   = afifo_r_data[i*W +: W];
        
        if (i == N-1)
        assign r_ready                  = afifo_r_ready[i];
    end
    
    
    
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
    
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire w_ready,
    
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire r_ready
);
    AFIFOSeries #(
        .W(W),
        .N(N)
    ) AFIFOSeries(
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
endmodule

`ifdef SIM
module Testbench();
    localparam W = `Width;
    localparam N = `Count;
    
    reg rst_ = 1;
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
    
    initial forever #10 w_clk = !w_clk;
    initial forever #20 r_clk = !r_clk;
    
    initial begin
        forever begin
            wait(!w_clk);
            wait(w_clk);
            if (w_trigger && w_ready) begin
                $display("Wrote %0d", w_data);
                w_data = w_data+1;
            end
        end
    end
    
endmodule
`endif
