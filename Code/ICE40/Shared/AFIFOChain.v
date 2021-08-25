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

endmodule

`endif
