`define stringify(x) `"x```"

`define fits(container, value) ($size(container) >= $clog2(value+64'b1))

`ifdef SIM
    `define assert(cond) do if (!(cond)) begin $error("Assertion failed: %s (%s:%0d)", `stringify(cond), `__FILE__, `__LINE__); $finish; end while (0)
`else
    `define assert(cond)
`endif

`ifdef SIM
    `define finish $finish
`else
    `define finish
`endif
