module main(
    input logic clk,
    input logic rst,
    output logic out
);
    logic[31:0] ctr;
    
    always_ff @(posedge clk, negedge rst)
        if (~rst) ctr <= 0;
        else ctr <= ctr+1;
    
    assign out = ctr[31];
endmodule
