`ifndef Delay_v
`define Delay_v

module Delay #(
    parameter Count = 1
)(
    input wire in,
    output wire out
);
    wire[Count:0] bits;
    assign bits[0] = in;
    assign out = bits[Count];
    genvar i;
    for (i=0; i<Count; i=i+1) begin
        SB_LUT4 #(
            .LUT_INIT(16'bxxxx_xxxx_xxxx_xx10)
        ) SB_LUT4(
            .I3(1'b0),
            .I2(1'b0),
            .I1(1'b0),
            .I0(bits[i]),
            .O(bits[i+1])
        );
    end
endmodule

`endif
