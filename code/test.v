module main();
    logic[15:0] a;
    logic b;
    logic[15:0] c;
    // wire[2:0] meow = b+1;
    assign a = 16'b1111111111111111;
    assign b = 1;
    assign c = a&{16{b}};
  
    always @* begin
        wire[2:0] meow = b+1;
    end
  
  // initial
  //   begin
  //     #10;
  //     $display("%b", c);
  //     $finish ;
  //   end
endmodule
