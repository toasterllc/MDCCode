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
    reg[1:0] w_bits = 0;
    reg[1:0] w_rbits = 0;
    assign w_ok = |(~w_bits);
    always @(posedge w_clk) begin
        if (w_trigger && w_ok) begin
            mem[w_addr] <= w_data;
            w_addr <= w_addr+1;
            if (w_addr===8'h7F) w_bits[0] <= 1;
            if (w_addr===8'hFF) w_bits[1] <= 1;
        end
    end
    
    always @(posedge w_clk) begin
        
    end
    
    // ====================
    // Read domain
    // ====================
    reg[N-1:0] r_addr = 0;
    assign r_data = mem[r_addr];
    assign r_ok = 
    always @(posedge r_clk) begin
        if (r_trigger && r_ok) begin
            r_addr <= r_addr+1;
        end
    end
endmodule
