// module CRC7(
//     input wire clk,
//     input wire rst_,
//     input din,
//     output wire[6:0] dout,
//     output wire[6:0] doutNext
// );
//     reg[6:0] d = 0;
//     wire dx = din ^ d[6];
//     wire[6:0] dnext = { d[5], d[4], d[3], d[2]^dx, d[1], d[0], dx };
//     always @(posedge clk)
//         if (!rst_) d <= 0;
//         else d <= dnext;
//     assign dout = d;
//     assign doutNext = dnext;
// endmodule





module CRC7 #(
    parameter Delay = 0
)(
    input wire clk,
    input wire en,
    input din,
    output wire dout
);
    reg[6+Delay:0] d = 0;
    wire dx = (en ? din^d[6] : 0);
    always @(posedge clk) begin
        d <= d<<1;
        d[0] <= dx;
        d[3] <= dx^d[2];
    end
    assign dout = d[6+Delay];
endmodule