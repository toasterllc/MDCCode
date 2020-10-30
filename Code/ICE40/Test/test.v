// iverilog -o test.vvp -g2012 test.v ; ./test.vvp

parameter ClkFreq = 50000000;

module main();
    initial begin
        $display("Hello");
        $finish;
    end
endmodule
