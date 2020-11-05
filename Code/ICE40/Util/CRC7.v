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
    // Delay can be between [-3, infinity]
    // Negative delays are possible because the high 4 bits of the CRC
    // are a simple shift register, so we can peek ahead.
    // See CRC section of SD spec.
    parameter Delay = 0
)(
    input wire clk,
    input wire en,
    input din,
    output wire dout
);
    localparam PosDelay = (Delay > 0 ? Delay : 0);
    reg[6+PosDelay:0] d = 0;
    wire dx = (en ? din^d[6] : 0);
    always @(posedge clk) begin
        d <= d<<1;
        d[0] <= dx;
        d[3] <= dx^d[2];
    end
    assign dout = d[6+Delay];
endmodule
