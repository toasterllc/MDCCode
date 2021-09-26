`ifndef FletcherChecksum_v
`define FletcherChecksum_v

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
    reg[WidthHalf-1:0] a = 0;
    reg[WidthHalf-1:0] a2 = 0;
    reg[WidthHalf-1:0] b = 0;
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
        
        end else if (en) begin
            a <= ({1'b0,a} + din) % {WidthHalf{'1}};
            b <= ({1'b0,b} + a  ) % {WidthHalf{'1}};
            a2 <= a;
        end
    end
    assign dout[Width-1:WidthHalf]  = b;
    assign dout[WidthHalf-1:0]      = a2;
endmodule

`endif
