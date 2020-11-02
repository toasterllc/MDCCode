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
    parameter DelayA = 0,
    parameter DelayB = 0
)(
    input wire clk,
    input wire en,
    input din,
    output wire doutA,
    output wire doutB
);
    localparam PosDelayA = (DelayA > 0 ? DelayA : 0);
    localparam PosDelayB = (DelayB > 0 ? DelayB : 0);
    localparam PosDelay = (PosDelayA > PosDelayB ? PosDelayA : PosDelayB);
    reg[6+PosDelay:0] d = 0;
    wire dx = (en ? din^d[6] : 0);
    always @(posedge clk) begin
        d <= d<<1;
        d[0] <= dx;
        d[3] <= dx^d[2];
    end
    assign doutA = d[6+DelayA];
    assign doutB = d[6+DelayB];
endmodule
