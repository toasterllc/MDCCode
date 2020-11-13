// iverilog -o test.vvp -g2012 test.v ; ./test.vvp

`define FieldLen(domain, subdomain)         FieldLen_``domain``_``subdomain``
`define FieldLen(A, B)                 8
`define FieldLen(C, D)                 9

module main();
    initial begin
        $display("Hello ABC %0d", `FieldLen(Msg2, Type));
        $finish;
    end
endmodule
