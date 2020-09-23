// module CRC16(
//     input wire clk,
//     input wire rst_,
//     input din,
//     output wire[15:0] dout,
//     output wire[15:0] doutNext
// );
//     reg[15:0] d = 0;
//     wire dx = din^d[15];
//     wire[15:0] dnext = { d[14], d[13], d[12], d[11]^dx, d[10], d[9], d[8], d[7], d[6], d[5], d[4]^dx, d[3], d[2], d[1], d[0], dx };
//     always @(posedge clk)
//         if (!rst_) d <= 0;
//         else d <= dnext;
//     assign dout = d;
//     assign doutNext = dnext;
// endmodule



module CRC16 #(
    parameter Delay = 0
)(
    input wire clk,
    input wire en,
    input din,
    output wire dout
);
    reg[15+Delay:0] d = 0;
    wire dx = (en ? din^d[15] : 0);
    always @(posedge clk) begin
        d <= d<<1;
        d[0] <= dx;
        d[5] <= dx^d[4];
        d[12] <= dx^d[11];
    end
    assign dout = d[15+Delay];
endmodule
