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
    input wire rst_, // Toggle
    
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
    // Write handling
    // ====================
    reg[N-1:0] w_baddr=0, w_gaddr=0, w_gaddrDelayed=0; // Write address (binary, gray)
    wire[N-1:0] w_baddrNext = (w_trigger&&w_ready ? w_baddr+1'b1 : w_baddr);
    always @(posedge w_clk, negedge rst_) begin
        if (!rst_) begin
            w_gaddrDelayed <= 0;
            w_baddr <= 0;
            w_gaddr <= 0;
        
        end else begin
            w_gaddrDelayed <= w_gaddr;
            w_baddr <= w_baddrNext;
            w_gaddr <= (w_baddrNext>>1)^w_baddrNext;
        end
    end
    
    reg[1:0] w_readyReg_ = 0; // Inverted logic so we come out of reset with w_ready==true
    always @(posedge w_clk, negedge a_full_)
        if (!a_full_) w_readyReg_ <= ~0;
        else w_readyReg_ <= (w_readyReg_<<1)|(!a_full_);
    
    assign w_ready = !w_readyReg_[$size(w_readyReg_)-1];
    
    // ====================
    // Read handling
    // ====================
    // Don't init r_baddr=0, since that breaks RAM inference with Icestorm,
    // since it thinks r_baddr is async instead of being clocked by r_clk
    reg[N-1:0] r_baddr, r_gaddr=0, r_gaddrDelayed=0; // Read addresses (binary, gray)
    
`ifdef SIM
    initial r_baddr = 0; // For simulation (see r_baddr comment above)
`endif
    
    wire[N-1:0] r_baddrNext = (r_trigger&&r_ready ? r_baddr+1'b1 : r_baddr);
    always @(posedge r_clk) begin
        if (!rst_) begin
            r_gaddrDelayed <= 0;
            r_baddr <= 0;
            r_gaddr <= 0;
        
        end else begin
            r_gaddrDelayed <= r_gaddr;
            r_baddr <= r_baddrNext;
            r_gaddr <= (r_baddrNext>>1)^r_baddrNext;
        end
    end
    
    reg[2:0] r_readyReg = 0;
    always @(posedge r_clk, negedge a_empty_)
        if (!a_empty_) r_readyReg <= 0;
        else r_readyReg <= (r_readyReg<<1)|a_empty_;
    
    assign r_ready = `LeftBit(r_readyReg, 0);
    
    // ====================
    // Async signal generation
    // ====================
    reg a_dir = 0;
    wire a_dirSet = (w_gaddr[N-1]^r_gaddrDelayed[N-2]) && ~(w_gaddr[N-2]^r_gaddrDelayed[N-1]);
    wire a_dirClr = (~(w_gaddrDelayed[N-1]^r_gaddr[N-2]) && (w_gaddrDelayed[N-2]^r_gaddr[N-1])) || !rst_;
    
    always @(posedge a_dirSet, posedge a_dirClr)
        if (a_dirClr) a_dir <= 0;
        else a_dir <= 1;
    
    assign a_full_ = ~((w_gaddr == r_gaddrDelayed) && a_dir);
    assign a_empty_ = ~((w_gaddrDelayed == r_gaddr) && !a_dir);
    
    // ====================
    // RAM
    // ====================
    SB_RAM40_4K SB_RAM40_4K(
        .WCLK(w_clk),
        .WCLKE(1'b1),
        .WE(w_trigger && w_ready),
        .WADDR({3'b000, w_baddr}),
        .WDATA(w_data),
        .MASK(16'h0000),
        
        .RCLK(r_clk),
        .RCLKE(1'b1),
        .RE(1'b1),
        .RADDR({3'b000, r_baddrNext}),
        .RDATA(r_data)
    );
    
    
    
    
    
    
    // reg dir = 0;
    // wire arok = (r_gaddr!=w_gaddrDelayed) || dir; // Read OK == not empty
    // wire awok = (r_gaddrDelayed!=w_gaddr) || !dir; // Write OK == not full
    //
    // // ICESTORM: USED TO WORK, NOW FAILS (WFAST, RSLOW)
    // // ICECUBE: WORKS
    // wire dirclr = (r_gaddrDelayed[N]!=w_gaddrDelayed[N-1]) && (r_gaddrDelayed[N-1]==w_gaddrDelayed[N]);
    // wire dirset = (r_gaddrDelayed[N]==w_gaddrDelayed[N-1]) && (r_gaddrDelayed[N-1]!=w_gaddrDelayed[N]);
    //
    // // // ICESTORM: WORKS
    // // // ICECUBE: WORKS
    // // wire dirclr = (r_gaddr[N]!=w_gaddrDelayed[N-1]) && (r_gaddr[N-1]==w_gaddrDelayed[N]);
    // // wire dirset = (r_gaddrDelayed[N]==w_gaddr[N-1]) && (r_gaddrDelayed[N-1]!=w_gaddr[N]);
    //
    // // // ICESTORM: FAILS (WFAST, RSLOW)
    // // // ICECUBE: WORKS
    // // wire dirclr = (r_gaddrDelayed[N]!=w_gaddr[N-1]) && (r_gaddrDelayed[N-1]==w_gaddr[N]);
    // // wire dirset = (r_gaddr[N]==w_gaddrDelayed[N-1]) && (r_gaddr[N-1]!=w_gaddrDelayed[N]);
    //
    // // // ICESTORM: FAILS (WFAST, RSLOW)
    // // // ICECUBE: WORKS
    // // wire dirclr = (r_gaddr[N]!=w_gaddr[N-1]) && (r_gaddr[N-1]==w_gaddr[N]);
    // // wire dirset = (r_gaddr[N]==w_gaddr[N-1]) && (r_gaddr[N-1]!=w_gaddr[N]);
    //
    // always @(posedge dirclr, posedge dirset) begin
    //     if (dirclr) dir <= 0;
    //     else dir <= 1;
    // end
endmodule

`endif
