module CRC7(
    input wire clk,
    input wire en,
    input din,
    output wire[6:0] dout,
    output wire[6:0] doutNext
);
    reg[6:0] d = 0;
    wire dx = din ^ d[6];
    wire[6:0] dnext = { d[5], d[4], d[3], d[2] ^ dx, d[1], d[0], dx };
    always @(posedge clk, negedge en)
        if (!en) d <= 0;
        else d <= dnext;
    assign dout = d;
    assign doutNext = dnext;
endmodule
