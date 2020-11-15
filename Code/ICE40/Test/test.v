// iverilog -o test.vvp -g2012 test.v ; ./test.vvp

`define FieldLen(domain, subdomain)         FieldLen_``domain``_``subdomain``
`define FieldLen(A, B)                 8
`define FieldLen(C, D)                 9

module MyModule #(
    parameter ClkFreq = 24_000_000,
    localparam CmdCapture = 1'b0,
    localparam CmdReadout = 1'b1
)();
endmodule

module main();
    initial begin
        $display("Hello ABC %0d", MyModule.ClkFreq);
        $finish;
    end
endmodule
