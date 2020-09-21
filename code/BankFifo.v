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
    reg[1:0] bits = 0;
    wire full = &bits;
    wire empty = !bits;
    
    // ====================
    // Write domain
    // ====================
    reg[N-1:0] w_addr = 0;
    wire[N-1:0] w_addrNext = w_addr+1;
    assign w_ok = !full;
    always @(posedge w_clk) begin
        if (w_trigger && w_ok) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addrNext;
        end
    end
    
    
    
    
    
    // ====================
    // Read domain
    // ====================
    reg[N-1:0] r_addr; // Don't initialize, otherwise yosys doesn't infer a BRAM
    wire[N-1:0] r_addrNext = r_addr+1;
`ifdef SIM
    initial r_addr = 8'h00;
`endif
    assign r_data = mem[r_addr];
    assign r_ok = !empty;
    always @(posedge r_clk) begin
        if (r_trigger && r_ok) begin
            r_addr <= r_addrNext;
        end
    end
    
    
    wire w_bank = w_addr[N-1];
    wire r_bank = r_addr[N-1];
    always @(posedge w_bank, posedge r_bank) begin
        if (w_bank) bits[0] <= 1;
        else bits[0] <= 0;
    end
    
    always @(negedge w_bank, negedge r_bank) begin
        if (!w_bank) bits[1] <= 1;
        else bits[1] <= 0;
    end
    
endmodule
