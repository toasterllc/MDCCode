// TODO: fix w_trigger/w_done mechanism? currently it's not possible to write a single word since the `w_done` is delayed right? instead we should output a signal indicated that the trigger was accepted on the same clock cycle that it was accepted

module BankFifo(
    input wire w_clk,
    input wire w_trigger,
    input wire[15:0] w_data,
    output reg w_done = 0,
    
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
    
    reg w_rbank=0, w_rbankTmp=0;
    always @(posedge w_clk)
        {w_rbank, w_rbankTmp} <= {w_rbankTmp, r_bank};
    
    reg w_primed = 0;
    
    always @(posedge w_clk) begin
        w_done <= 0; // Pulse
        w_primed <= w_bank|w_primed;
        if (w_trigger && (w_bank!==w_rbank || !w_primed)) begin
            mem[w_addr] <= w_data;
            w_done <= 1;
            w_addr <= w_addr+1;
        end
    end
    
    
    
    
    
    // ====================
    // Read domain
    // ====================
    reg[7:0] r_addr = 0;
    wire r_bank = r_addr[7];
    
    reg r_wbank=0, r_wbankTmp=0;
    always @(posedge r_clk)
        {r_wbank, r_wbankTmp} <= {r_wbankTmp, w_bank};
    
    always @(posedge r_clk) begin
        r_done <= 0; // Pulse
        if (r_trigger && r_bank!==r_wbank) begin
            r_data <= mem[r_addr];
            r_done <= 1;
            r_addr <= r_addr+1;
        end
    end

endmodule
