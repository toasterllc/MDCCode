// Generates a single-cycle pulse on `out`, in clock domain `clk`,
// when the async signal `in` toggles.
`define TogglePulse(out, in, edge, clk)                         \
    reg in = 0;                                                 \
    reg[2:0] `Var3(out,in,clk) = 0;                             \
    wire out = `Var3(out,in,clk)[2]!==`Var3(out,in,clk)[1];     \
    always @(edge clk)                                          \
        `Var3(out,in,clk) <= (`Var3(out,in,clk)<<1)|in
