`include "Util.v"
`include "ClockGen.v"
`include "Sync.v"
`include "AFIFO.v"
`include "ToggleAck.v"
`include "TogglePulse.v"
`timescale 1ns/1ps

module AFIFOSeries #(
    parameter W = 16
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
    wire        afifo1_rst_;
    wire        afifo1_w_clk;
    wire        afifo1_w_trigger;
    wire[W-1:0] afifo1_w_data;
    wire        afifo1_w_ready;
    wire        afifo1_r_clk;
    wire        afifo1_r_trigger;
    wire[W-1:0] afifo1_r_data;
    wire        afifo1_r_ready;
    
    wire        afifo2_rst_;
    wire        afifo2_w_clk;
    wire        afifo2_w_trigger;
    wire[W-1:0] afifo2_w_data;
    wire        afifo2_w_ready;
    wire        afifo2_r_clk;
    wire        afifo2_r_trigger;
    wire[W-1:0] afifo2_r_data;
    wire        afifo2_r_ready;
    
    assign afifo1_rst_          = rst_;
    assign afifo1_w_clk         = w_clk;
    assign afifo1_w_trigger     = w_trigger;
    assign afifo1_w_data        = w_data;
    assign w_ready              = afifo1_w_ready;
    assign afifo1_r_clk         = w_clk;
    assign afifo1_r_trigger     = afifo2_w_ready;
    
    assign afifo2_rst_          = rst_;
    assign afifo2_w_clk         = w_clk;
    assign afifo2_w_trigger     = afifo1_r_ready;
    assign afifo2_w_data        = afifo1_r_data;
    assign afifo2_r_clk         = r_clk;
    assign afifo2_r_trigger     = r_trigger;
    assign r_data               = afifo2_r_data;
    assign r_ready              = afifo2_r_ready;
    
    AFIFO #(
        .W(W)
    ) AFIFO1 (
        .rst_(afifo1_rst_),
        
        .w_clk(afifo1_w_clk),
        .w_trigger(afifo1_w_trigger),
        .w_data(afifo1_w_data),
        .w_ready(afifo1_w_ready),
        
        .r_clk(afifo1_r_clk),
        .r_trigger(afifo1_r_trigger),
        .r_data(afifo1_r_data),
        .r_ready(afifo1_r_ready)
    );
    
    AFIFO #(
        .W(W)
    ) AFIFO2 (
        .rst_(afifo2_rst_),
        
        .w_clk(afifo2_w_clk),
        .w_trigger(afifo2_w_trigger),
        .w_data(afifo2_w_data),
        .w_ready(afifo2_w_ready),
        
        .r_clk(afifo2_r_clk),
        .r_trigger(afifo2_r_trigger),
        .r_data(afifo2_r_data),
        .r_ready(afifo2_r_ready)
    );

endmodule

module Top #(
    parameter W = 16
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
    AFIFOSeries AFIFOSeries(
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
    localparam W = 16;
    
    wire rst_;
    wire w_clk;
    wire w_trigger;
    wire[W-1:0] w_data;
    wire w_ready;
    wire r_clk;
    wire r_trigger;
    wire[W-1:0] r_data;
    wire r_ready;
    
    Top #(.W(W)) Top(
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
endmodule
`endif


