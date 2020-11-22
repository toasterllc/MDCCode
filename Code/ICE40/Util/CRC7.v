`ifndef CRC7_v
`define CRC7_v

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





// module CRC7 #(
//     // Delay can be between [-3, infinity]
//     // Negative delays are possible because the high 4 bits of the CRC
//     // are a simple shift register, so we can peek ahead.
//     // See CRC section of SD spec.
//     parameter Delay = 0
// )(
//     input wire clk,
//     input wire en,
//     input din,
//     output wire dout
// );
//     localparam PosDelay = (Delay > 0 ? Delay : 0);
//     reg[6+PosDelay:0] d = 0;
//     wire dx = (en ? din^d[6] : 0);
//     reg enPrev = 0;
//     wire rst_ = !(!enPrev && en);
//     always @(posedge clk) enPrev <= en;
//     always @(posedge clk, negedge rst_) begin
//         if (!rst_) d <= 0;
//         else begin
//             d <= d<<1;
//             d[0] <= dx;
//             d[3] <= dx^d[2];
//         end
//     end
//     assign dout = d[6+Delay];
// endmodule











module CRC7 #(
    // Delay can be between [-3, infinity]
    // Negative delays are possible because the high 4 bits of the CRC
    // are a simple shift register, so we can peek ahead.
    // See CRC section of SD spec.
    parameter Delay = 0
)(
    input wire clk,
    input wire rst,
    input wire en,
    input din,
    output wire dout
);
    localparam PosDelay = (Delay > 0 ? Delay : 0);
    reg[6+PosDelay:0] d = 0;
    wire dx = (en ? din^d[6] : 0);
    always @(posedge clk) begin
        if (rst) begin
            d <= 0;
        
        end else begin
            d <= d<<1;
            d[0] <= dx;
            d[3] <= dx^d[2];
        end
    end
    assign dout = d[6+Delay];
endmodule




`endif
