// iverilog -o test.vvp -g2012 test.v ; ./test.vvp

module main();
    localparam ClockFrequency = 100000000;
    
    function [63:0] Clocks;
        input [63:0] t;
        // wire[63:0] n = (t*ClockFrequency)/1000000000;
        // Icarus Verilog doesn't support `logic` type for arguments for
        // some reason, so use `reg` instead.
        // We can't use `integer` because it's only 32 bits.
        // n = (t*ClockFrequency)/1000000000;
        Clocks = (t*ClockFrequency)/1000000000;
    endfunction
    
    
    // logic[15:0] a;
    // logic b;
    // logic[15:0] c;
    // // wire[2:0] meow = b+1;
    // assign a = 16'b1111111111111111;
    // assign b = 1;
    // assign c = a&{16{b}};
    //
    // always @* begin
    //     wire[2:0] meow = b+1;
    // end
  
    // initial
    // begin
    // #10;
    // $display("%b", c);
    // $finish ;
    // end
    //
    
    initial begin
        $display("HERRO %0d", Clocks(15625));
        $finish;
    end

endmodule
