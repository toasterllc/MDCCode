module BankFifo #(
    parameter W=16, // Word size
    parameter N=8   // Word count (2^N)
)(
    input wire w_clk,
    input wire w_trigger,
    input wire[15:0] w_data,
    output wire w_ok,
    
    input wire r_clk,
    input wire r_trigger,
    output wire[15:0] r_data,
    output wire r_ok
);
    reg[W-1:0] mem[0:(1<<N)-1];
    
    // ====================
    // Write domain
    // ====================
    reg[N-1:0] w_addr = 0;
    wire w_bank = w_addr[N-1];
    reg w_lastBank = 0;
    
    reg w_rswap=0, w_rswapTmp=0;
    always @(posedge w_clk)
        {w_rswap, w_rswapTmp} <= {w_rswapTmp, r_swap};
    
    wire w_swap = (w_bank!==w_lastBank);
    assign w_ok = !w_swap || w_rswap;
    always @(posedge w_clk) begin
        if (w_swap && w_rswap)
            w_lastBank <= !w_lastBank;
        
        if (w_trigger && w_ok) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addr+1;
        end
    end
    
    
    
    
    
    // ====================
    // Read domain
    // ====================
    reg[N-1:0] r_addr; // Don't initialize, otherwise yosys doesn't infer a BRAM
`ifdef SIM
    initial r_addr = 8'h00;
`endif
    wire r_bank = r_addr[N-1];
    reg r_lastBank_ = 0;
    
    reg r_wswap=0, r_wswapTmp=0;
    always @(posedge r_clk)
        {r_wswap, r_wswapTmp} <= {r_wswapTmp, w_swap};
    
    wire r_swap = (r_bank!==!r_lastBank_);
    assign r_data = mem[r_addr];
    assign r_ok = !r_swap || r_wswap;
    always @(posedge r_clk) begin
        if (r_swap && r_wswap)
            r_lastBank_ <= !r_lastBank_;
        
        if (r_trigger && r_ok)
            r_addr <= r_addr+1;
    end

endmodule
