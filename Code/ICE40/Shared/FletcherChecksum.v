`ifndef FletcherChecksum_v
`define FletcherChecksum_v

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
    reg[WidthHalf:0]    asum = 0;
    reg[WidthHalf:0]    bsum = 0;
    reg[WidthHalf-1:0]  amod = 0;
    reg[WidthHalf-1:0]  bmod = 0;
    reg[WidthHalf-1:0]  amoddelayed = 0;
    always @(posedge clk) begin
        if (rst) begin
            asum <= 0;
            bsum <= 0;
            amod <= 0;
            bmod <= 0;
            amoddelayed <= 0;
        
        end else if (en) begin
            asum <= asum+din;
            bsum <= asum+bsum;
            
            if (&asum[WidthHalf:1]) begin
                // Subtract 255*2, leaving only the least significant bit
                amod <= asum[0];
            end else if (asum[WidthHalf] || &asum[WidthHalf-1:0]) begin
                // Subtract 255
                amod <= asum-{WidthHalf{'1}};
            end else begin
                amod <= asum;
            end
            
            if (&bsum[WidthHalf:1]) begin
                // Subtract 255*2, leaving only the least significant bit
                bmod <= bsum[0];
            end else if (bsum[WidthHalf] || &bsum[WidthHalf-1:0]) begin
                // Subtract 255
                bmod <= bsum-{WidthHalf{'1}};
            end else begin
                bmod <= bsum;
            end
            
            // amod <= (asum[WidthHalf] || &asum[WidthHalf-1:0] ? asum-{WidthHalf{'1}} : asum);
            // bmod <= (bsum[WidthHalf] || &bsum[WidthHalf-1:0] ? bsum-{WidthHalf{'1}} : bsum);
            
            amoddelayed <= amod;
        end
    end
    assign dout[Width-1:WidthHalf]  = bmod;
    assign dout[WidthHalf-1:0]      = amoddelayed;
endmodule

`endif
