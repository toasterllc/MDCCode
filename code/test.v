module main;
  logic[15:0] a;
  logic b;
  logic[15:0] c;
  assign a = 16'b1111111111111111;
  assign b = 1;
  assign c = a&{16{b}};
  initial 
    begin
      #10;
      $display("%b", c);
      $finish ;
    end
endmodule