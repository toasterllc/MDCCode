`ifndef GrayCode_v
`define GrayCode_v

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

`endif
