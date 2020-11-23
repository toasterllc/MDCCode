`ifndef BankFIFO_v
`define BankFIFO_v

`include "TogglePulse.v"

module BankFIFO #(
    parameter W=16, // Word size
    parameter N=8   // Word count (2^N)
)(
    // Reset port (clock domain: async)
    input wire          rst, // Toggle
    output reg          rst_done = 0, // Toggle
    
    // Write port (clock domain: `w_clk`)
    input wire          w_clk,
    output wire         w_ready,
    input wire          w_trigger,
    input wire[W-1:0]   w_data,
    output wire         w_bank,
    
    // Read port (clock domain: `r_clk`)
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
    reg w_rst = 0;
    reg w_rstAck=0, w_rstAckTmp=0, w_rstAckPrev=0;
    reg r_rst=0, r_rstTmp=0;
    `TogglePulse(w_rstTrigger, rst, posedge, w_clk);
    always @(posedge w_clk) begin
        if (w_rstTrigger) w_rst <= 1;
        // Synchronize `r_rst` into `w_rstAck`, representing the
        // acknowledgement of the reset from the read domain.
        {w_rstAck, w_rstAckTmp} <= {w_rstAckTmp, r_rst};
        // Clear `w_rstReq` upon the ack from the read domain
        if (w_rstAck) w_rst <= 0;
        // We're done resetting when the ack goes 1->0
        w_rstAckPrev <= w_rstAck;
        if (w_rstAckPrev && !w_rstAck) rst_done <= !rst_done;
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
