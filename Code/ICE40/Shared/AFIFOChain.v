`ifndef AFIFOChain_v
`define AFIFOChain_v

`include "Util.v"
`include "AFIFO.v"
`include "Sync.v"

module AFIFOChain #(
    parameter W = 16,   // Word width
    parameter N = 2,    // FIFO count
    
    parameter W_Thresh = N/2,   // Write threshold (default: half of the FIFO is empty)
    parameter R_Thresh = N/2    // Read threshold (default: half of the FIFO is full)
)(
    input wire rst_,
    input wire prop_clk, // Propagation clock; supply the faster of `w_clk` and `r_clk`
    
    // Write port
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire w_ready,
    output wire w_thresh, // Whether >=W_Thresh FIFOs are empty
    
    // Read port
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire r_ready,
    output wire r_thresh, // Whether >=R_Thresh FIFOs are full
    
    // Async port
    output wire async_w_thresh, // Async version of `w_thresh`
    output wire async_r_thresh  // Async version of `r_thresh`
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
    
    assign w_ready  = afifo_w_ready[0];
    assign r_data   = afifo_r_data[(N-1)*W +: W];
    assign r_ready  = afifo_r_ready[N-1];
    
    localparam W_ThreshIdx = W_Thresh-1;
    localparam R_ThreshIdx = N-R_Thresh;
    
    assign async_w_thresh = !afifo_r_ready[W_ThreshIdx];
    assign async_r_thresh = !afifo_w_ready[R_ThreshIdx];
    
    `Sync(w_threshSynced, async_w_thresh, posedge, w_clk);
    `Sync(r_threshSynced, async_r_thresh, posedge, r_clk);
    
    assign w_thresh = w_threshSynced;
    assign r_thresh = r_threshSynced;
endmodule

`endif
