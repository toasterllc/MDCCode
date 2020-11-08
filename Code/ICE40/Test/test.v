// iverilog -o test.vvp -g2012 test.v ; ./test.vvp

parameter ClkFreq = 50000000;

module main();
    function [63:0] MyFun1;
        input [63:0] a;
        MyFun1 = a;
    endfunction
    
    function [63:0] MyFun2;
        input [63:0] a;
        input [63:0] b;
        MyFun2 = a[b];
    endfunction
    
    initial begin
        reg[63:0] a = MyFun2(16'd12345, 4);
        // wire[] a = MyFun1(16'd12345);
        // $display("Hello %b", a[4]);
        $display("Hello %b", a);
        // $display("Hello %b", {1{16'd12345}}[4:4]);
        $finish;
    end
endmodule
