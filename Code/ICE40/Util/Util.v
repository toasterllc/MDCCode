`define Var1(a)         var_``a``
`define Var2(a,b)       var_``a``_``b``
`define Var3(a,b,c)     var_``a``_``b``_``c``
`define Var4(a,b,c,d)   var_``a``_``b``_``c``_``d``

`define Max2(a,y)           ((a) > (y) ? (a) : (y))
`define Max3(a,b,y)         (`Max2(a,b)         > (y) ? `Max2(a,b)          : (y))
`define Max4(a,b,c,y)       (`Max3(a,b,c)       > (y) ? `Max3(a,b,c)        : (y))
`define Max5(a,b,c,d,y)     (`Max4(a,b,c,d)     > (y) ? `Max4(a,b,c,d)      : (y))
`define Max6(a,b,c,d,e,y)   (`Max5(a,b,c,d,e)   > (y) ? `Max5(a,b,c,d,e)    : (y))
`define Max(a,y)            `Max2(a,y)

// RegWidth: returns the width of a register to store the given values
`define RegWidth(y)             $clog2((y)+1'b1)
`define RegWidth2(a,y)          (`RegWidth(a) > `RegWidth(y) ? `RegWidth(a) : `RegWidth(y))
`define RegWidth3(a,b,y)        (`RegWidth2(a,b)       > (y) ? `RegWidth2(a,b)         : (y))
`define RegWidth4(a,b,c,y)      (`RegWidth3(a,b,c)     > (y) ? `RegWidth3(a,b,c)       : (y))
`define RegWidth5(a,b,c,d,y)    (`RegWidth4(a,b,c,d)   > (y) ? `RegWidth4(a,b,c,d)     : (y))
`define RegWidth6(a,b,c,d,e,y)  (`RegWidth5(a,b,c,d,e) > (y) ? `RegWidth5(a,b,c,d,e)   : (y))

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

function [63:0] DivCeil;
    input [63:0] n;
    input [63:0] d;
    begin
        DivCeil = (n+d-1)/d;
    end
endfunction
