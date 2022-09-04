`ifndef Util_v
`define Util_v

`define Var1(a)         var_``a``
`define Var2(a,b)       var_``a``_``b``
`define Var3(a,b,c)     var_``a``_``b``_``c``
`define Var4(a,b,c,d)   var_``a``_``b``_``c``_``d``

// Max: returns the larger of N values
`define Max2(a,y)           ((a) > (y) ? (a) : (y))
`define Max3(a,b,y)         (`Max2(a,b)         > (y) ? `Max2(a,b)          : (y))
`define Max4(a,b,c,y)       (`Max3(a,b,c)       > (y) ? `Max3(a,b,c)        : (y))
`define Max5(a,b,c,d,y)     (`Max4(a,b,c,d)     > (y) ? `Max4(a,b,c,d)      : (y))
`define Max6(a,b,c,d,e,y)   (`Max5(a,b,c,d,e)   > (y) ? `Max5(a,b,c,d,e)    : (y))
`define Max7(a,b,c,d,e,f,y) (`Max6(a,b,c,d,e,f) > (y) ? `Max6(a,b,c,d,e,f)  : (y))
`define Max(a,y)            `Max2(a,y)

// RegWidth: returns the width of a register to store the given values
`define RegWidth(y)                             `Max(64'b1, $clog2((y)+64'b1)) // Enforce min width of 1
`define RegWidth2(a,y)                          (`RegWidth(a)                       > `RegWidth(y) ? `RegWidth(a)                       : `RegWidth(y))
`define RegWidth3(a,b,y)                        (`RegWidth2(a,b)                    > `RegWidth(y) ? `RegWidth2(a,b)                    : `RegWidth(y))
`define RegWidth4(a,b,c,y)                      (`RegWidth3(a,b,c)                  > `RegWidth(y) ? `RegWidth3(a,b,c)                  : `RegWidth(y))
`define RegWidth5(a,b,c,d,y)                    (`RegWidth4(a,b,c,d)                > `RegWidth(y) ? `RegWidth4(a,b,c,d)                : `RegWidth(y))
`define RegWidth6(a,b,c,d,e,y)                  (`RegWidth5(a,b,c,d,e)              > `RegWidth(y) ? `RegWidth5(a,b,c,d,e)              : `RegWidth(y))
`define RegWidth7(a,b,c,d,e,f,y)                (`RegWidth6(a,b,c,d,e,f)            > `RegWidth(y) ? `RegWidth6(a,b,c,d,e,f)            : `RegWidth(y))
`define RegWidth8(a,b,c,d,e,f,g,y)              (`RegWidth7(a,b,c,d,e,f,g)          > `RegWidth(y) ? `RegWidth7(a,b,c,d,e,f,g)          : `RegWidth(y))
`define RegWidth9(a,b,c,d,e,f,g,h,y)            (`RegWidth8(a,b,c,d,e,f,g,h)        > `RegWidth(y) ? `RegWidth8(a,b,c,d,e,f,g,h)        : `RegWidth(y))
`define RegWidth10(a,b,c,d,e,f,g,h,i,y)         (`RegWidth9(a,b,c,d,e,f,g,h,i)      > `RegWidth(y) ? `RegWidth9(a,b,c,d,e,f,g,h,i)      : `RegWidth(y))
`define RegWidth11(a,b,c,d,e,f,g,h,i,j,y)       (`RegWidth10(a,b,c,d,e,f,g,h,i,j)   > `RegWidth(y) ? `RegWidth10(a,b,c,d,e,f,g,h,i,j)   : `RegWidth(y))
`define RegWidth12(a,b,c,d,e,f,g,h,i,j,k,y)     (`RegWidth11(a,b,c,d,e,f,g,h,i,j,k) > `RegWidth(y) ? `RegWidth11(a,b,c,d,e,f,g,h,i,j,k) : `RegWidth(y))

// Sub: a-b, clipping to 0
`define Sub(a,b) ((a) > (b) ? ((a)-(b)) : 0)

`define Stringify(x) `"x```"

`define Fits(container, value) ($size(container) >= `RegWidth(value))

`define LeftBit(r, idx)         r[$size(r)-(idx)-1]
`define LeftBits(r, idx, len)   r[($size(r)-(idx)-1) -: (len)]

`define RightBit(r, idx)        r[(idx)]
`define RightBits(r, idx, len)  r[(idx)+(len)-1 -: (len)]

`ifdef SIM
`define ValidBits(a) (((a)^(a)) === 0) // 1 if there are no x's or z's
`else
`define ValidBits(a) (1'b1) // Always 1 when not simulating
`endif

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

`define DivCeil(n, d) (((n)+(d)-1)/(d))
`define Ceil(val, mult) (`DivCeil((val), (mult)) * (mult))

// Padding: returns the amount of padding necessary to bring `len` up to a multiple of `mult`
`define Padding(len, mult) (((mult) - ((len) % (mult))) % (mult))

// Clocks() returns the minimum number of `freq` clock cycles
// for >= `ns` nanoseconds to elapse. For example, if ns=5ns, and
// the clock period is 4ns, Clocks(freq=250e6,ns=5,sub=0) will return 2.
// `sub` is subtracted from that value, with the result clipped to zero.
function[63:0] Clocks;
    input[63:0] freq;
    input[63:0] ns;
    input[63:0] sub;
    begin
        Clocks = `DivCeil(freq*ns, 1_000_000_000);
        if (Clocks >= sub) Clocks = Clocks-sub;
        else Clocks = 0;
    end
endfunction

`endif
