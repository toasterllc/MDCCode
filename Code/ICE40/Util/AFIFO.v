`ifndef AFIFO_v
`define AFIFO_v

// Based on Clifford E. Cummings paper:
//   http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf
module AFIFO #(
    parameter W=16, // Word width
    parameter N=8   // Word count (2^N)
)(
    // Reset port (clock domain: async)
    input wire rst_,
    
    input wire w_clk,           // Write clock
    input wire w_trigger,       // Write trigger
    input wire[W-1:0] w_data,   // Write data
    output wire w_ready,        // Write OK (space available -- not full)
    
    input wire r_clk,           // Read clock
    input wire r_trigger,       // Read trigger
    output wire[W-1:0] r_data,  // Read data
    output wire r_ready         // Read OK (data available -- not empty)
);
    reg[W-1:0] mem[0:(1<<N)-1];
    
    // ====================
    // Write handling
    // ====================
    reg[N:0] w_baddr=0, w_gaddr=0, w_gaddrDelayed=0; // Write address (binary, gray, gray delayed)
    wire[N:0] w_baddrNext = w_baddr+1'b1;
    always @(posedge w_clk, negedge rst_) begin
        if (!rst_) begin
            w_baddr <= 0;
            w_gaddr <= 0;
            w_gaddrDelayed <= 0;
        
        end else begin
            w_gaddrDelayed <= w_gaddr;
            if (w_trigger & w_ready) begin
                mem[w_baddr[N-1:0]] <= w_data;
                w_baddr <= w_baddrNext;
                w_gaddr <= (w_baddrNext>>1)^w_baddrNext;
            end
        end
    end
    
    reg[1:0] w_readyReg_ = 0; // Inverted logic so we come out of reset with w_ready==true
    always @(posedge w_clk, negedge w_readyAsync)
        if (!w_readyAsync) w_readyReg_ <= 2'b11;
        else w_readyReg_ <= (w_readyReg_<<1)|1'b0;
    
    assign w_ready = !w_readyReg_[1];
    
    // ====================
    // Read handling
    // ====================
    // Don't init r_baddr=0, since that breaks RAM inference with Icestorm,
    // since it thinks r_baddr is async instead of being clocked by r_clk
    reg[N:0] r_baddr, r_gaddr=0, r_gaddrDelayed=0; // Read addresses (binary, gray)
    
`ifdef SIM
    initial r_baddr = 0; // For simulation (see r_baddr comment above)
`endif
    
    wire[N:0] r_baddrNext = r_baddr+1'b1;
    always @(posedge r_clk, negedge rst_) begin
        if (!rst_) begin
            r_baddr <= 0;
            r_gaddr <= 0;
            r_gaddrDelayed <= 0;
        
        end else begin
            r_gaddrDelayed <= r_gaddr;
            if (r_trigger & r_ready) begin
                r_baddr <= r_baddrNext;
                r_gaddr <= (r_baddrNext>>1)^r_baddrNext;
            end
        end
    end
    
    reg[1:0] r_readyReg = 0;
    always @(posedge r_clk, negedge r_readyAsync)
        if (!r_readyAsync) r_readyReg <= 2'b00;
        else r_readyReg <= (r_readyReg<<1)|1'b1;
    
    assign r_data = mem[r_baddr[N-1:0]];
    assign r_ready = r_readyReg[1];
    
    // ====================
    // Async signal generation
    // ====================
    wire r_empty = (r_gaddr == w_gaddrDelayed);
    wire w_full = (w_gaddr == {~r_gaddrDelayed[N:N-1], r_gaddrDelayed[N-2:0]});
    
    wire r_readyAsync = !r_empty; // Read OK == !empty
    wire w_readyAsync = !w_full || !rst_; // Write OK == !full
    
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
