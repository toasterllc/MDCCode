`ifndef BankFIFO_v
`define BankFIFO_v

module BankFIFO #(
    parameter W=16, // Word size
    parameter N=8   // Word count (2^N)
)(
    input wire          w_clk,
    input wire          w_trigger,
    input wire[W-1:0]   w_data,
    output wire         w_ok,
    output wire         w_bank,
    
    input wire          r_clk,
    input wire          r_trigger,
    output wire[W-1:0]  r_data,
    output wire         r_ok,
    output wire         r_bank
);
    reg[W-1:0] mem[0:(1<<N)-1];
    reg dir = 0;
    
    // ====================
    // Write domain
    // ====================
    reg[N-1:0] w_addr = 0;
    reg w_rbank=0, w_rbankTmp=0;
    assign w_bank = w_addr[N-1];
    assign w_ok = w_bank!==w_rbank || !dir;
    always @(posedge w_clk) begin
        if (w_trigger && w_ok) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addr+1;
        end
        
        {w_rbank, w_rbankTmp} <= {w_rbankTmp, r_bank};
    end
    
    // ====================
    // Read domain
    // ====================
    reg[N-1:0] r_addr;
`ifdef SIM
    initial r_addr = 0;
`endif
    reg r_wbank=0, r_wbankTmp=0;
    assign r_bank = r_addr[N-1];
    assign r_data = mem[r_addr];
    assign r_ok = r_bank!==r_wbank || dir;
    always @(posedge r_clk) begin
        if (r_trigger && r_ok)
            r_addr <= r_addr+1;
        
        {r_wbank, r_wbankTmp} <= {r_wbankTmp, w_bank};
    end
    
    
    // ====================
    // `dir` Handling
    // ====================
    wire[1:0] r = r_addr[N-1:N-2];
    wire[1:0] w = w_addr[N-1:N-2];
    wire emptyish = (r===2'b01 && w===2'b10) || (r===2'b11 && w===2'b00);
    wire fullish = (w===2'b01 && r===2'b10) || (w===2'b11 && r===2'b00);
    
    always @(posedge emptyish, posedge fullish)
        if (emptyish) dir <= 0;
        else dir <= 1;
    
endmodule

`endif
