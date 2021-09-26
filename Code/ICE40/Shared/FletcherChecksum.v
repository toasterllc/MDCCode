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
    // wire[WidthHalf:0] asum = a+din;
    // // OnesComplementAdder #(
    // //     .Width(WidthHalf)
    // // ) OnesComplementAdder_asum(
    // //     .a(a),
    // //     .b(din),
    // //     .y(asum)
    // // );
    //
    // wire[WidthHalf:0] bsum = a+b;
    // // OnesComplementAdder #(
    // //     .Width(WidthHalf)
    // // ) OnesComplementAdder_bsum(
    // //     .a(a),
    // //     .b(b),
    // //     .y(bsum)
    // // );
    
    reg[Width:0] a = 0;
    reg[Width:0] adelayed = 0;
    reg[Width:0] b = 0;
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
        
        end else if (en) begin
            a <= (a+din);
            b <= (a+b);
            adelayed <= a;
        end
    end
    assign dout[Width-1:WidthHalf]  = b % {WidthHalf{'1}};
    assign dout[WidthHalf-1:0]      = adelayed % {WidthHalf{'1}};
endmodule

`endif
