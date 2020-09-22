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
    reg dir = 0;
    
    // ====================
    // Write domain
    // ====================
    reg[N-1:0] w_addr = 0;
    wire w_bank = w_addr[N-1];
    reg w_rbank = 0;
    assign w_ok = w_bank!==w_rbank || !dir;
    always @(posedge w_clk) begin
        if (w_trigger && w_ok) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addr+1;
        end
    end
    
    reg w_rbankTmp = 0;
    always @(posedge w_clk)
        {w_rbank, w_rbankTmp} <= {w_rbankTmp, r_bank};
    
    // ====================
    // Read domain
    // ====================
    reg[N-1:0] r_addr;
`ifdef SIM
    initial r_addr = 0;
`endif
    wire r_bank = r_addr[N-1];
    reg r_wbank = 0;
    assign r_data = mem[r_addr];
    assign r_ok = r_bank!==r_wbank || dir;
    always @(posedge r_clk) begin
        if (r_trigger && r_ok) begin
            r_addr <= r_addr+1;
        end
    end
    
    reg r_wbankTmp = 0;
    always @(posedge r_clk)
        {r_wbank, r_wbankTmp} <= {r_wbankTmp, w_bank};
    
    
    wire[1:0] r = r_addr[N-1:N-2];
    wire[1:0] w = w_addr[N-1:N-2];
    wire almostEmpty = (r===2'b01 && w===2'b10) || (r===2'b11 && w===2'b00);
    wire almostFull = (w===2'b01 && r===2'b10) || (w===2'b11 && r===2'b00);
    
    always @(posedge almostEmpty, posedge almostFull)
        if (almostEmpty) dir <= 0;
        else dir <= 1;
    
endmodule
