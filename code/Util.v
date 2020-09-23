`define Var1(a)         var_``a``
`define Var2(a,b)       var_``a``_``b``
`define Var3(a,b,c)     var_``a``_``b``_``c``
`define Var4(a,b,c,d)   var_``a``_``b``_``c``_``d``

`define Stringify(x) `"x```"

`define Fits(container, value) ($size(container) >= $clog2(value+64'b1))

`ifdef SIM
    `define Assert(cond) do if (!(cond)) begin $error("Assertion failed: %s (%s:%0d)", `Stringify(cond), `__FILE__, `__LINE__); $finish; end while (0)
`else
    `define Assert(cond)
`endif

`ifdef SIM
    `define Finish $finish
`else
    `define Finish
`endif
