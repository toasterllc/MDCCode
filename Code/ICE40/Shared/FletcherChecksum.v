`ifndef FletcherChecksum_v
`define FletcherChecksum_v

`include "Util.v"

module OnesComplementAdder #(
    parameter Width         = 32
)(
    input wire[Width-1:0]   a,
    input wire[Width-1:0]   b,
    output wire[Width-1:0]  y
);
    wire[Width:0] sum = a+b;
    wire carry = sum[Width];
    // assign y = sum;
    assign y = sum+carry;
endmodule

module FletcherChecksum #(
    parameter Width         = 32,
    localparam WidthHalf    = Width/2
)(
    input wire                  clk,
    input wire                  rst,
    input wire                  en,
    input wire[WidthHalf-1:0]   din,
    output wire[Width-1:0]      dout
);
    reg[WidthHalf+2:0]  asum = 0;
    reg[WidthHalf+2:0]  asumtmp = 0;
    reg[WidthHalf+2:0]  bsum = 0;
    reg[WidthHalf-1:0]  asumdelayed = 0;
    
    wire[WidthHalf-1:0] asub = (!`LeftBit(asum,0) ? {WidthHalf{'1}} : 0);
    wire[WidthHalf-1:0] bsub = (!`LeftBit(bsum,0) ? {WidthHalf{'1}} : 0);
    
    wire[WidthHalf-1:0] a = asum[WidthHalf-1:0]-1;
    wire[WidthHalf-1:0] b = bsum[WidthHalf-1:0]-1;
    
    always @(posedge clk) begin
        if (rst) begin
            asum <= 0;
            bsum <= 0;
            asumdelayed <= 0;
        
        end begin
            if (en) begin
                asum <= ((asum-asub)+din);
                asumtmp <= (asum+din);
                bsum <= ((bsum-bsub)+asumtmp);
            end else begin
                asum <= asum-asub;
                bsum <= bsum-bsub;
            end
            
            asumdelayed <= asum;
            
            $display("bsum:%0d bsub:%0d  |  asum:%0d asub:%0d  |  din:%0d  |  en:%0d", bsum, bsub, asum, asub, din, en);
        end
    end
    // assign dout = {bsum[WidthHalf-1:0], asum[WidthHalf-1:0]};
    assign dout = {b, a};
endmodule

`endif
