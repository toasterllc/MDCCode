// Synchronizes an async signal `in` into the clock domain `clk`
`define Sync(out, in, edge, clk)                                \
    reg in=0, out=0, `Var3(out,in,clk)=0;                       \
    always @(edge clk)                                          \
        {out, `Var3(out,in,clk)} <= {`Var3(out,in,clk), in}
