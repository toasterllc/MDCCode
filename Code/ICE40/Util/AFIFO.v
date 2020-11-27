`ifndef AFIFO_v
`define AFIFO_v

`include "TogglePulse.v"

// Based on Clifford E. Cummings paper:
//   http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf
module AFIFO #(
    parameter W=16, // Word width
    parameter N=8   // Word count (2^N)
)(
    // Reset port (clock domain: async)
    input wire rst, // Toggle
    output reg rst_done = 0, // Toggle
    
    input wire w_clk,               // Write clock
    input wire w_trigger,           // Write trigger
    input wire[W-1:0] w_data,       // Write data
    output wire w_ready,            // Write OK (space available -- not full)
    
    input wire r_clk,               // Read clock
    input wire r_trigger,           // Read trigger
    output wire[W-1:0] r_data,      // Read data
    output wire r_ready             // Read OK (data available -- not empty)
);
    // ====================
    // Reset Handling
    // ====================
    reg w_rst = 0;
    reg w_rstAck=0, w_rstAckTmp=0, w_rstAckPrev=0;
    reg r_rst=0, r_rstTmp=0;
    `TogglePulse(w_rstTrigger, rst, posedge, w_clk);
    always @(posedge w_clk) begin
        if (w_rstTrigger) w_rst <= 1;
        // Synchronize `r_rst` into `w_rstAck`, representing the
        // acknowledgement of the reset from the read domain.
        {w_rstAck, w_rstAckTmp} <= {w_rstAckTmp, r_rst};
        // Clear `w_rstReq` upon the ack from the read domain
        if (w_rstAck) w_rst <= 0;
        // We're done resetting when the ack goes 1->0
        w_rstAckPrev <= w_rstAck;
        if (w_rstAckPrev && !w_rstAck) rst_done <= !rst_done;
    end
    
    always @(posedge r_clk) begin
        {r_rst, r_rstTmp} <= {r_rstTmp, w_rst};
    end
    
    // ====================
    // Write handling
    // ====================
    reg[N:0] w_baddr=0, w_gaddr=0; // Write address (binary, gray)
    wire[N:0] w_baddrNext = (w_trigger&&w_ready ? w_baddr+1'b1 : w_baddr);
    wire[N:0] w_gaddrNext = (w_baddrNext>>1)^w_baddrNext;
    reg[N:0] w_rgaddr=0, w_rgaddrTmp=0;
    reg w_full = 0;
    always @(posedge w_clk) begin
        if (w_rst) begin
            {w_baddr, w_gaddr} <= 0;
            {w_rgaddr, w_rgaddrTmp} <= 0;
            w_full <= 0;
        end else begin
            {w_baddr, w_gaddr} <= {w_baddrNext, w_gaddrNext};
            {w_rgaddr, w_rgaddrTmp} <= {w_rgaddrTmp, r_gaddr};
            w_full <= (w_gaddrNext === {~w_rgaddr[N:N-1], w_rgaddr[N-2:0]});
        end
    end
    
    assign w_ready = !w_full;
    
    // ====================
    // Read handling
    // ====================
    // Don't init r_baddr=0, since that breaks RAM inference with Icestorm,
    // since it thinks r_baddr is async instead of being clocked by r_clk
    reg[N:0] r_baddr=0, r_gaddr=0; // Read addresses (binary, gray)
    wire[N:0] r_baddrNext = (r_trigger&&r_ready ? r_baddr+1'b1 : r_baddr);
    wire[N:0] r_gaddrNext = (r_baddrNext>>1)^r_baddrNext;
    reg[N:0] r_wgaddr=0, r_wgaddrTmp=0;
    reg r_empty_ = 0;
    always @(posedge r_clk) begin
        if (r_rst) begin
            {r_baddr, r_gaddr} <= 0;
            {r_wgaddr, r_wgaddrTmp} <= 0;
            r_empty_ <= 0;
        end else begin
            {r_baddr, r_gaddr} <= {r_baddrNext, r_gaddrNext};
            {r_wgaddr, r_wgaddrTmp} <= {r_wgaddrTmp, w_gaddr};
            r_empty_ <= !(r_gaddrNext == r_wgaddr);
        end
    end
    
    assign r_ready = r_empty_;
    
    // ====================
    // RAM
    // ====================
    SB_RAM40_4K SB_RAM40_4K(
        .WCLK(w_clk),
        .WCLKE(1'b1),
        .WE(w_trigger && w_ready),
        .WADDR({3'b000, w_baddr[N-1:0]}),
        .WDATA(w_data),
        .MASK(16'h0000),
        
        .RCLK(r_clk),
        .RCLKE(1'b1),
        .RE(1'b1),
        .RADDR({3'b000, r_baddrNext[N-1:0]}),
        .RDATA(r_data)
    );
endmodule

`endif
