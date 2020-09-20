module BankFifo #(
    parameter W=16, // Word size
    parameter N=8   // Word count (2^N)
)(
    input wire w_clk,
    input wire w_trigger,
    input wire[15:0] w_data,
    output wire w_done,
    
    input wire r_clk,
    input wire r_trigger,
    output wire[15:0] r_data,
    output wire r_done
);
    reg[W-1:0] mem[0:(1<<N)-1];
    
    
    
    
    // ====================
    // Write domain
    // ====================
    reg[N-1:0] w_addr = 0;
    wire w_bank = w_addr[N-1];
    reg w_lastBank = 0;
    
    reg w_rbank=0, w_rbankTmp=0;
    always @(posedge w_clk)
        {w_rbank, w_rbankTmp} <= {w_rbankTmp, r_bank};
    
    assign w_done = (w_trigger && (w_bank===w_lastBank || w_bank!==w_rbank));
    always @(posedge w_clk) begin
        if (w_done) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addr+1;
            w_lastBank <= w_bank;
        end
    end
    
    
    
    
    
    // ====================
    // Read domain
    // ====================
    reg[N-1:0] r_addr; // Don't initialize, otherwise yosys doesn't infer a BRAM
`ifdef SIM
    initial r_addr = 0;
`endif
    
    wire r_bank = r_addr[N-1];
    reg r_lastBank_ = 0;
    
    reg r_wbank=0, r_wbankTmp=0;
    always @(posedge r_clk)
        {r_wbank, r_wbankTmp} <= {r_wbankTmp, w_bank};
    
    assign r_done = (r_trigger && (r_bank===!r_lastBank_ || r_bank!==r_wbank));
    assign r_data = mem[r_addr];
    always @(posedge r_clk) begin
        if (r_done) begin
            r_addr <= r_addr+1;
            r_lastBank_ <= !r_bank;
        end
    end

endmodule
