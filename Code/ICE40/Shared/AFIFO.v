`include "Util.v"

`ifndef AFIFO_v
`define AFIFO_v

`define AFIFO_CapacityBits  4096
`define AFIFO_CapacityBytes (`AFIFO_CapacityBits/8)

// Based on Clifford E. Cummings paper:
//   http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf
module AFIFO #(
    parameter W = 16 // Word width; allowed values: 16, 8, 4, 2
)(
    // Reset port (clock domain: async)
    input wire rst_,
    
    input wire w_clk,               // Write clock
    input wire w_trigger,           // Write trigger
    input wire[W-1:0] w_data,       // Write data
    output wire w_ready,            // Write OK (space available -- not full)
    
    input wire r_clk,               // Read clock
    input wire r_trigger,           // Read trigger
    output wire[W-1:0] r_data,      // Read data
    output wire r_ready             // Read OK (data available -- not empty)
);
`ifdef SIM
    initial begin
        if (W==16 || W==8 || W==4 || W==2);
        else begin
            $display("AFIFO: invalid width: %0d", W);
            `Finish;
        end
    end
`endif
    
    // Note that `N` is used directly in instantiations, not `N-1`, because we want an extra bit
    localparam N = `RegWidth((`AFIFO_CapacityBits/W)-1);
    
    // ====================
    // Write handling
    // ====================
    reg[N:0] w_baddr=0, w_gaddr=0; // Write address (binary, gray)
    wire[N:0] w_baddrNext = (w_trigger&&w_ready ? w_baddr+1'b1 : w_baddr);
    wire[N:0] w_gaddrNext = (w_baddrNext>>1)^w_baddrNext;
    reg[N:0] w_rgaddr=0, w_rgaddrTmp=0;
    reg w_full = 0;
    always @(posedge w_clk, negedge rst_) begin
        if (!rst_) begin
            {w_baddr, w_gaddr} <= 0;
            {w_rgaddr, w_rgaddrTmp} <= 0;
            w_full <= 0;
        end else begin
            {w_baddr, w_gaddr} <= {w_baddrNext, w_gaddrNext};
            {w_rgaddr, w_rgaddrTmp} <= {w_rgaddrTmp, r_gaddr};
            w_full <= (w_gaddrNext === {~w_rgaddr[N:N-1], w_rgaddr[N-2:0]});
        end
    end
    
    assign w_ready = !w_full;
    
    // ====================
    // Read handling
    // ====================
    reg[N:0] r_baddr=0, r_gaddr=0; // Read addresses (binary, gray)
    wire[N:0] r_baddrNext = (r_trigger&&r_ready ? r_baddr+1'b1 : r_baddr);
    wire[N:0] r_gaddrNext = (r_baddrNext>>1)^r_baddrNext;
    reg[N:0] r_wgaddr=0, r_wgaddrTmp=0;
    reg r_empty_ = 0;
    always @(posedge r_clk, negedge rst_) begin
        if (!rst_) begin
            {r_baddr, r_gaddr} <= 0;
            {r_wgaddr, r_wgaddrTmp} <= 0;
            r_empty_ <= 0;
        end else begin
            {r_baddr, r_gaddr} <= {r_baddrNext, r_gaddrNext};
            {r_wgaddr, r_wgaddrTmp} <= {r_wgaddrTmp, w_gaddr};
            r_empty_ <= !(r_gaddrNext === r_wgaddr);
        end
    end
    
    assign r_ready = r_empty_;
    
    // ====================
    // RAM
    // ====================
    function[1:0] MODE;
        case (W)
        16: MODE = 0;
        8:  MODE = 1;
        4:  MODE = 2;
        2:  MODE = 3;
        endcase
    endfunction
    
    wire[10:0] WADDR = w_baddr[N-1:0];
    wire[10:0] RADDR = r_baddrNext[N-1:0];
    wire[15:0] WDATA;
    generate
        case (W)
        16: assign WDATA = {
            w_data[15], w_data[14], w_data[13], w_data[12],
            w_data[11], w_data[10], w_data[ 9], w_data[ 8],
            w_data[ 7], w_data[ 6], w_data[ 5], w_data[ 4],
            w_data[ 3], w_data[ 2], w_data[ 1], w_data[ 0]
        };
        
        8: assign WDATA = {
            1'bx,       w_data[7],  1'bx,       w_data[6],
            1'bx,       w_data[5],  1'bx,       w_data[4],
            1'bx,       w_data[3],  1'bx,       w_data[2],
            1'bx,       w_data[1],  1'bx,       w_data[0]
        };
        
        4: assign WDATA = {
            1'bx,       1'bx,       w_data[3],  1'bx,
            1'bx,       1'bx,       w_data[2],  1'bx,
            1'bx,       1'bx,       w_data[1],  1'bx,
            1'bx,       1'bx,       w_data[0],  1'bx
        };
        
        2: assign WDATA = {
            1'bx,       1'bx,       1'bx,       1'bx,
            w_data[1],  1'bx,       1'bx,       1'bx,
            1'bx,       1'bx,       1'bx,       1'bx,
            w_data[0],  1'bx,       1'bx,       1'bx
        };
        endcase
    endgenerate
    
    wire[15:0] RDATA;
    generate
        case (W)
        16: assign r_data = RDATA[15:0];
        8:  assign r_data = {RDATA[14], RDATA[12], RDATA[10], RDATA[8], RDATA[6], RDATA[4], RDATA[2], RDATA[0]};
        4:  assign r_data = {RDATA[13], RDATA[9], RDATA[5], RDATA[1]};
        2:  assign r_data = {RDATA[11], RDATA[3]};
        endcase
    endgenerate
    
    // We use WCLKE/RCLKE instead of WE/RE, because apparently WE/RE don't always
    // work correctly due to a silicon bug.
    // From https://github.com/nmigen/nmigen/issues/14:
    //   "Yosys does not use RE or WE at all. Instead, RCLKE and WCLKE are used. This is due to a silicon bug."
    //   "iCECube does not use RE or WE at all, similarly to Yosys."
    SB_RAM40_4K #(
        .READ_MODE(MODE()),
        .WRITE_MODE(MODE())
    ) SB_RAM40_4K(
        .WCLK(w_clk),
        .WCLKE(w_trigger && w_ready),
        .WE(1'b1),
        .WADDR(WADDR),
        .WDATA(WDATA),
        .MASK(16'h0000),
        
        .RCLK(r_clk),
        .RCLKE(1'b1),
        .RE(1'b1),
        .RADDR(RADDR),
        .RDATA(RDATA)
    );
endmodule

`endif
