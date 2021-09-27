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
            
            // $display("[FletcherChecksum]\t\t bsum:%0d bsub:%0d \t asum:%0d asub:%0d \t din:%0d \t\t en:%0d", bsum, bsub, asum, asub, din, en);
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
    reg[WidthHalf-1:0] a = 0;
    reg[WidthHalf-1:0] b = 0;
    reg enprev = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
            enprev <= 0;
        
        end begin
            enprev <= en;
            if (en) a <= ({1'b0,a}+din) % {WidthHalf{'1}};
            if (enprev) b <= ({1'b0,b}+a) % {WidthHalf{'1}};
            $display("[FletcherChecksumCorrect]\t b:%h \t\t a:%h \t\t din:%h \t\t en:%h", b, a, din, en);
        end
    end
    assign dout = {b, a};
endmodule

`endif
