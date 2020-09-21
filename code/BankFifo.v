module BankFifo #(
    parameter W=16, // Word size
    parameter N=8   // Word count (2^N)
)(
    input wire w_clk,
    input wire w_trigger,
    input wire[W-1:0] w_data,
    output wire w_ok,
    
    input wire r_clk,
    input wire r_trigger,
    output wire[W-1:0] r_data,
    output wire r_ok
);
    reg[W-1:0] mem[0:(1<<N)-1];
    
    // ====================
    // Write domain
    // ====================
    reg[N-1:0] w_addr = 0;
    reg[1:0] w_bits = 0;
    reg[1:0] w_rbits=0, w_rbitsTmp=0;
    assign w_ok = (w_bits[0]===w_rbits[0]) || (w_bits[1]===w_rbits[1]);
    always @(posedge w_clk) begin
        if (w_trigger && w_ok) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addr+1;
        end
    end
    
    
    
    
    // ====================
    // Read domain
    // ====================
    reg[N-1:0] r_addr;
`ifdef SIM
    initial r_addr = 0;
`endif
    reg[1:0] r_bits = 0;
    reg[1:0] r_wbits=0, r_wbitsTmp=0;
    assign r_data = mem[r_addr];
    assign r_ok = (r_bits[0]!==r_wbits[0]) || (r_bits[1]!==r_wbits[1]);
    always @(posedge r_clk) begin
        if (r_trigger && r_ok) begin
            r_addr <= r_addr+1;
        end
    end
    
    
    
    
    
    // ====================
    // w_bits
    // ====================
    always @(posedge w_clk) begin
        if (&w_addr[N-2:0]) begin
            case (w_addr[N-1])
            0:  w_bits[0] <= !w_bits[0];
            1:  w_bits[1] <= !w_bits[1];
            endcase
        end
    end
    
    // ====================
    // r_bits
    // ====================
    always @(posedge r_clk) begin
        if (&r_addr[N-2:0]) begin
            case (r_addr[N-1])
            0:  r_bits[0] <= !r_bits[0];
            1:  r_bits[1] <= !r_bits[1];
            endcase
        end
    end
    
    // ====================
    // w_bits -> r_wbits
    // ====================
    always @(posedge r_clk) begin
        {r_wbits, r_wbitsTmp} <= {r_wbitsTmp, w_bits};
    end
    
    // ====================
    // r_bits -> w_rbits
    // ====================
    always @(posedge w_clk) begin
        {w_rbits, w_rbitsTmp} <= {w_rbitsTmp, r_bits};
    end

endmodule
