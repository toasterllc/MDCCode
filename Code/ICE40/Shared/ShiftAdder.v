`ifndef ShiftAdder_v
`define ShiftAdder_v

module Adder #(
    parameter N = 4
)(
    input wire[N-1:0] a,
    input wire[N-1:0] b,
    input wire cin,
    output wire[N-1:0] sum,
    output wire cout
);
    wire[N:0] s = a+b+cin;
    assign sum = s[N-1:0];
    assign cout = s[N];
endmodule

module ShiftAdder #(
    parameter W = 16,   // Total width
    parameter N = 4     // Width of a single adder
)(
    input wire clk,
    input wire[W-1:0] a,
    input wire[W-1:0] b,
    output reg[W-1:0] sum = 0
);
    localparam S = W/N; // Number of adders
    genvar i;
    reg[S-1:0] cin = 0;
    wire[W-1:0] sumParts;
    wire[S-1:0] cout;
    for (i=0; i<S; i=i+1) begin
        Adder #(
            .N(N)
        ) adder (
            .a(a[((i+1)*N)-1 : i*N]),
            .b(b[((i+1)*N)-1 : i*N]),
            .cin(cin[i]),
            .sum(sumParts[((i+1)*N)-1 : i*N]),
            .cout(cout[i])
        );
    end
    
    always @(posedge clk) begin
        cin[S-1:1] <= cout[S-2:0];
        sum <= sumParts;
    end
endmodule

`endif
