`ifndef BankFIFO_v
`define BankFIFO_v

module BankFIFO #(
    parameter W=16, // Word size
    parameter N=8   // Word count (2^N)
)(
    input wire          rst_, // Async
    
    // TODO: consider re-ordering: w_clk, w_data, w_trigger, w_ready, w_bank
    input wire          w_clk,
    output wire         w_ready,
    input wire          w_trigger,
    input wire[W-1:0]   w_data,
    output wire         w_bank,
    
    // TODO: consider re-ordering: r_clk, r_data, r_trigger, r_ready, r_bank
    input wire          r_clk,
    output wire         r_ready,
    input wire          r_trigger,
    output wire[W-1:0]  r_data,
    output wire         r_bank
);
    reg[W-1:0] mem[0:(1<<N)-1];
    reg dir = 0;
    
    
    
    // ====================
    // Reset Handling
    // ====================
    reg w_rst=0, w_rstTmp=0;
    reg w_rstAck=0, w_rstAckTmp=0;
    reg r_rst=0, r_rstTmp=0;
    always @(posedge w_clk, negedge rst_) begin
        if (!rst_) w_rstTmp <= 1;
        else begin
            {w_rstAck, w_rstAckTmp} <= {w_rstAckTmp, r_rst};
            {w_rst, w_rstTmp} <= {w_rstTmp, (w_rstAck ? 1'b0 : w_rstTmp)};
        end
    end
    
    always @(posedge r_clk) begin
        {r_rst, r_rstTmp} <= {r_rstTmp, w_rst};
    end
    
    
    
    // ====================
    // Write domain
    // ====================
    reg[N-1:0] w_addr = 0;
    reg w_rbank=0, w_rbankTmp=0;
    assign w_bank = w_addr[N-1];
    assign w_ready = !w_rst && (w_bank!==w_rbank || !dir);
    always @(posedge w_clk) begin
        if (w_rst) begin
            w_addr <= 0;
            w_rbank <= 0;
            w_rbankTmp <= 0;
        
        end else begin
            if (w_trigger && w_ready) begin
                mem[w_addr] <= w_data;
                w_addr <= w_addr+1;
            end
            
            {w_rbank, w_rbankTmp} <= {w_rbankTmp, r_bank};
        end
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
    assign r_ready = !r_rst && (r_bank!==r_wbank || dir);
    always @(posedge r_clk) begin
        if (r_rst) begin
            r_addr <= 0;
            r_wbank <= 0;
            r_wbankTmp <= 0;
        
        end else begin
            if (r_trigger && r_ready)
                r_addr <= r_addr+1;
            
            {r_wbank, r_wbankTmp} <= {r_wbankTmp, w_bank};
        end
    end
    
    // ====================
    // `dir` Handling
    // ====================
    wire[1:0] r = r_addr[N-1:N-2];
    wire[1:0] w = w_addr[N-1:N-2];
    wire emptyish = (r===2'b00 && w===2'b01) ||
                    (r===2'b01 && w===2'b10) ||
                    (r===2'b10 && w===2'b11) ||
                    (r===2'b11 && w===2'b00) ||
                    r_rst;
    
    wire fullish =  (w===2'b00 && r===2'b01) ||
                    (w===2'b01 && r===2'b10) ||
                    (w===2'b10 && r===2'b11) ||
                    (w===2'b11 && r===2'b00);
    
    always @(posedge emptyish, posedge fullish)
        if (emptyish) dir <= 0;
        else dir <= 1;
    
endmodule

`endif
