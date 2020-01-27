`timescale 1ns/1ps

`define stringify(x) `"x```"
`define assert(cond) if (!(cond)) $error("Assertion failed: %s (%s:%0d)", `stringify(cond), `__FILE__, `__LINE__)

// module Bin2Gray(
//     input logic[3:0] d,
//     output logic[3:0] q
// );
//     assign q[3] = d[3];
//     assign q[2] = d[3] ^ d[2];
//     assign q[1] = d[2] ^ d[1];
//     assign q[0] = d[1] ^ d[0];
// endmodule
//
// module Gray2Bin(
//     input logic[3:0] d,
//     output logic[3:0] q
// );
//     assign q[3] = d[3];
//     assign q[2] = d[3] ^ d[2];
//     assign q[1] = d[3] ^ d[2] ^ d[1];
//     assign q[0] = d[3] ^ d[2] ^ d[1] ^ d[0];
// endmodule

module Bin2Gray(
    input logic[Width-1:0] d,
    output logic[Width-1:0] q
);
    parameter Width = 4;
    integer i;
    always @* begin
        q[Width-1] = d[Width-1];
        for (i=0; i<Width-1; i=i+1) begin
            q[i] = d[i+1] ^ d[i];
        end
    end
endmodule

module Gray2Bin(
    input logic[Width-1:0] d,
    output logic[Width-1:0] q
);
    parameter Width = 4;
    integer i;
    always @* begin
        q[Width-1] = d[Width-1];
        for (i=Width-2; i>=0; i=i-1) begin
            q[i] = q[i+1] ^ d[i];
        end
    end

endmodule



module GrayCodeTest(
    input logic[3:0] d,
    output logic[3:0] q1,
    output logic[3:0] q2
);
    Bin2Gray x1(.d(d), .q(q1));
    Gray2Bin x2(.d(d), .q(q2));
endmodule

`ifdef SIM

function integer CountOnes;
    input [127:0] val;
    CountOnes = 0;
    for (int i=0; i<$size(val); i++) begin
        CountOnes += val[i];
    end
endfunction

module GrayCodeTestSim(
);
    logic[3:0] d;
    logic[3:0] q;
    logic[3:0] q2;
    
    logic[3:0] lastq;
    
    Bin2Gray b2g(.d(d), .q(q));
    Gray2Bin g2b(.d(q), .q(q2));
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, GrayCodeTestSim);
       lastq = 0;
       
       for (int i=0; i<16; i++) begin
           
           d = i; #1;
           $display("%b -> %b -> %b [diff: %0d bits]", d, q, q2, CountOnes(q^lastq));
           `assert(d == q2);
           `assert(i==0 || CountOnes(q^lastq)==1);
           
           lastq = q;
       end
       
       // #10000000;
//        #200000000;
//        #2300000000;
       $finish;
    end
endmodule

`endif