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
    
    reg w_rbank=0, w_rbankTmp=0;
    always @(posedge w_clk)
        {w_rbank, w_rbankTmp} <= {w_rbankTmp, r_bank};
    
    reg w_rok=0, w_rokTmp=0;
    always @(posedge w_clk)
        {w_rok, w_rokTmp} <= {w_rokTmp, r_ok};
    
    assign w_ok = (w_bank!==w_rbank || !w_rok);
    always @(posedge w_clk) begin
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
    initial r_addr = 0;
`endif
    wire r_bank = r_addr[N-1];
    
    reg r_wbank=0, r_wbankTmp=0;
    always @(posedge r_clk)
        {r_wbank, r_wbankTmp} <= {r_wbankTmp, w_bank};
    
    reg r_wok=0, r_wokTmp=0;
    always @(posedge r_clk)
        {r_wok, r_wokTmp} <= {r_wokTmp, w_ok};
    
    assign r_ok = (r_bank!==r_wbank || !r_wok);
    assign r_data = mem[r_addr];
    always @(posedge r_clk) begin
        if (r_trigger && r_ok) begin
            r_addr <= r_addr+1;
        end
    end

endmodule
