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
    reg[WidthHalf+2:0]  asum = 0;
    reg[WidthHalf+2:0]  bsum = 0;
    reg[WidthHalf-1:0]  asumdelayed = 0;
    
    reg[WidthHalf+2:0]  asub = 0;
    reg[WidthHalf+2:0]  bsub = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            asum <= 0;
            bsum <= 0;
            asumdelayed <= 0;
        
        end else if (en) begin
            asum <= ((asum-asub)+din);
            bsum <= ((asum-bsub)+bsum);
            
            if (&asum[WidthHalf:1]) begin
                // Subtract 255*2, leaving only the least significant bit
                asub <= {{WidthHalf{'1}}, 1'b0};
            end else if (asum[WidthHalf] || &asum[WidthHalf-1:0]) begin
                // Subtract 255
                asub <= {WidthHalf{'1}};
            end else begin
                // Subtract 0
                asub <= 0;
            end
            
            if (&bsum[WidthHalf:1]) begin
                // Subtract 255*2, leaving only the least significant bit
                bsub <= {{WidthHalf{'1}}, 1'b0};
            end else if (bsum[WidthHalf] || &bsum[WidthHalf-1:0]) begin
                // Subtract 255
                bsub <= {WidthHalf{'1}};
            end else begin
                // Subtract 0
                bsub <= 0;
            end
            
            asumdelayed <= asum;
        end
    end
    assign dout[Width-1:WidthHalf]  = bsum;
    assign dout[WidthHalf-1:0]      = asumdelayed;
endmodule

`endif
