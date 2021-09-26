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
    reg[WidthHalf-1:0]  asumdelayed = 0;
    
    wire[WidthHalf:0] a = asum+din;
    wire[WidthHalf:0] b = asum+bsum;
    
    always @(posedge clk) begin
        if (rst) begin
            asum <= 0;
            bsum <= 0;
            asumdelayed <= 0;
        
        end else if (en) begin
            if (&a[WidthHalf:1]) begin
                // Subtract 255*2, leaving only the least significant bit
                asum <= a[0];
            end else if (a[WidthHalf] || &a[WidthHalf-1:0]) begin
                // Subtract 255
                asum <= a-{WidthHalf{'1}};
            end else begin
                asum <= a;
            end
            
            if (&b[WidthHalf:1]) begin
                // Subtract 255*2, leaving only the least significant bit
                bsum <= b[0];
            end else if (b[WidthHalf] || &b[WidthHalf-1:0]) begin
                // Subtract 255
                bsum <= b-{WidthHalf{'1}};
            end else begin
                bsum <= b;
            end
            
            asumdelayed <= asum;
        end
    end
    assign dout[Width-1:WidthHalf]  = bsum;
    assign dout[WidthHalf-1:0]      = asumdelayed;
endmodule

`endif
