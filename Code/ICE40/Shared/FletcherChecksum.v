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
            
            $display("[FletcherChecksum]\t\t bsum:%0d bsub:%0d \t asum:%0d asub:%0d \t din:%0d \t\t en:%0d", bsum, bsub, asum, asub, din, en);
        end
    end
    // assign dout = {bsum[WidthHalf-1:0], asum[WidthHalf-1:0]};
    assign dout = {b, a};
endmodule

module FletcherChecksumCorrect #(
    parameter Width         = 32,
    localparam WidthHalf    = Width/2
)(
    input wire                  clk,
    input wire                  rst,
    input wire                  en,
    input wire[WidthHalf-1:0]   din,
    output wire[Width-1:0]      dout
);
    reg[WidthHalf-1:0] asum = 0;
    reg[WidthHalf-1:0] bsum = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            asum <= 0;
            bsum <= 0;
        
        end begin
            if (en) begin
                asum <= ({1'b0,asum}+din) % {WidthHalf{'1}};
                bsum <= ({1'b0,bsum}+asum) % {WidthHalf{'1}};
            end
            
            // $display("[FletcherChecksumCorrect]\t bsum:%0d \t\t asum:%0d \t\t din:%0d \t\t en:%0d", bsum, asum, din, en);
        end
    end
    assign dout = {bsum, asum};
endmodule

`endif
