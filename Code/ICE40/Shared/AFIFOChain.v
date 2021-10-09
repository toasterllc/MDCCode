`include "Util.v"
`include "AFIFO.v"
`include "Sync.v"

`ifndef AFIFOChain_v
`define AFIFOChain_v

module AFIFOChain #(
    parameter W = 16,
    parameter N = 2
)(
    input wire rst_,
    input wire prop_clk, // Propagation clock; supply the faster of `w_clk` and `r_clk`
    
    // Write port
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire[N-1] w_ready,
    output wire w_halfEmpty, // Whether half of the FIFO can be written
    
    // Read port
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire[N-1] r_ready
    output wire r_halfFull, // Whether half of the FIFO can be read
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
        assign afifo_w_clk[i]           = prop_clk;
        
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
        assign afifo_r_clk[i]           = prop_clk;
        else
        assign afifo_r_clk[i]           = r_clk;
    end
    
    assign w_ready  = afifo_w_ready;
    assign r_data   = afifo_r_data[(N-1)*W +: W];
    assign r_ready  = afifo_r_ready;
    
    // w_halfEmpty: whether the left half of the FIFO is empty
    //   == whether the middle-left AFIFO is empty
    //   == middle-left AFIFO's !r_ready
    
    // r_halfFull: whether the right half of the FIFO is full
    //   == whether the middle-right AFIFO is full
    //   == middle-right AFIFO's !w_ready
    
    localparam MiddleLeft   = (N/2)-1;
    localparam MiddleRight  = N/2;
    
    wire async_halfEmpty    = !afifo_r_ready[MiddleLeft];
    wire async_halfFull     = !afifo_w_ready[MiddleRight];
    
    `Sync(w_halfEmpty, async_halfEmpty, posedge, afifo_r_clk[MiddleLeft]);
    `Sync(r_halfFull, async_halfFull, posedge, afifo_w_clk[MiddleRight);
endmodule

`endif
