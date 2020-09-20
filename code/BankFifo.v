// TODO: fix w_trigger/w_done mechanism? currently it's not possible to write a single word since the `w_done` is delayed right? instead we should output a signal indicated that the trigger was accepted on the same clock cycle that it was accepted

module BankFifo(
    input wire w_clk,
    input wire w_trigger,
    input wire[15:0] w_data,
    output wire w_done,
    
    input wire r_clk,
    input wire r_trigger,
    output reg[15:0] r_data = 0,
    output reg r_done = 0
);
    reg[15:0] mem[0:255];
    
    
    
    
    // ====================
    // Write domain
    // ====================
    reg[7:0] w_addr = 0;
    wire w_bank = w_addr[7];
    reg w_lastBank = 0;
    
    reg w_rbank=0, w_rbankTmp=0;
    always @(posedge w_clk)
        {w_rbank, w_rbankTmp} <= {w_rbankTmp, r_bank};
    
    assign w_done = w_trigger && (w_bank===w_lastBank || w_bank!==w_rbank);
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
    reg[7:0] r_addr = 0;
    wire r_bank = r_addr[7];
    reg r_lastBank_ = 0;
    
    reg r_wbank=0, r_wbankTmp=0;
    always @(posedge r_clk)
        {r_wbank, r_wbankTmp} <= {r_wbankTmp, w_bank};
    
    always @(posedge r_clk) begin
        r_done <= 0; // Pulse
        if (r_trigger && (r_bank===!r_lastBank_ || r_bank!==r_wbank)) begin
            r_data <= mem[r_addr];
            r_done <= 1;
            r_addr <= r_addr+1;
            r_lastBank_ <= !r_bank;
        end
    end

endmodule
