// `out` is set (in the clock domain `clk`) when the async signal `in` toggles.
// `out` is cleared when `ack` is toggled.
`define ToggleAck(out, ack, in, edge, clk)                      \
    reg[1:0] `Var4(out,ack,in,clk) = 0;                         \
    reg ack=0;                                                  \
    wire out = (ack !== `Var4(out,ack,in,clk)[1]);              \
    always @(edge clk)                                          \
        `Var4(out,ack,in,clk) <= (`Var4(out,ack,in,clk)<<1)|in
