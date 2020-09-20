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
    wire w_swap = (w_bank !== w_lastBank);
    
    reg[1:0] w_rswapTmp = 0;
    reg w_rswapAck = 0;
    wire w_rswap = w_rswapTmp[1]!==w_rswapAck;
    always @(posedge w_clk)
        w_rswapTmp <= w_rswapTmp<<1|r_swap;
    
    assign w_ok = (!w_swap || w_rswap);
    always @(posedge w_clk) begin
        if (w_trigger && w_ok) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addr+1;
            w_lastBank <= w_bank;
            
            if (w_swap && w_rswap) w_rswapAck <= !w_rswapAck;
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
    reg r_lastBank = 1;
    wire r_swap = (r_bank !== r_lastBank);
    
    reg[1:0] r_wswapTmp = 0;
    reg r_wswapAck = 0;
    wire r_wswap = r_wswapTmp[1]!==r_wswapAck;
    always @(posedge r_clk)
        r_wswapTmp <= r_wswapTmp<<1|w_swap;
    
    assign r_ok = (!r_swap || r_wswap);
    assign r_data = mem[r_addr];
    always @(posedge r_clk) begin
        if (r_trigger && r_ok) begin
            r_addr <= r_addr+1;
            r_lastBank <= r_bank;
            
            if (r_swap && r_wswap) r_wswapAck <= !r_wswapAck;
        end
    end

endmodule
