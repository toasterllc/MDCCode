`ifndef FletcherChecksum_v
`define FletcherChecksum_v

`include "Util.v"

module FletcherChecksum #(
    parameter Width         = 32,
    localparam WidthHalf    = Width/2
)(
    input wire                  clk,
    input wire                  rst,
    input wire                  en,
    input wire[WidthHalf-1:0]   din,
    output wire[Width-1:0]      dout
);
    reg[WidthHalf+6:0] a = 0;
    reg[WidthHalf+6:0] asub = 0;
    
    reg[WidthHalf+6:0] b = 0;
    reg[WidthHalf+6:0] bsub = 0;
    
    reg enprev = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            asub <= 0;
            b <= 0;
            bsub <= 0;
            enprev <= 0;
        
        end else begin
            enprev <= en;
            
            if (en) begin
                a <= a + din - asub;
                asub <= (a>=255*2 ? 255*2 : 0);
            end
            
            if (enprev) begin
                b <= b + a - bsub;
                bsub <= (b>=255*3 ? 255*3 : 0);
            end
            
            $display("[FletcherChecksum]\t\t b:%h bsub:%h \t a:%h asub:%h \t din:%h \t\t rst:%h en:%h [checksum: %h]",
                b, bsub,
                a, asub,
                din, rst, en, dout);
        end
    end
    assign dout = {b[WidthHalf-1:0], a[WidthHalf-1:0]};
endmodule

module FletcherChecksumCorrect #(
    parameter Width         = 32,
    localparam WidthHalf    = Width/2
)(
    input wire                  clk,
    input wire                  rst,
    input wire                  en,
    input wire[WidthHalf-1:0]   din,
    output wire[Width-1:0]      dout
);
    reg[WidthHalf-1:0] a = 0;
    reg[WidthHalf-1:0] b = 0;
    reg enprev = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
            enprev <= 0;
        
        end else begin
            enprev <= en;
            if (en)     a <= ({1'b0,a}+din) % {WidthHalf{'1}};
            if (enprev) b <= ({1'b0,b}+a  ) % {WidthHalf{'1}};
            
            // $display("[FletcherChecksumCorrect]\t b:%h \t\t a:%h \t\t din:%h \t\t en:%h", b, a, din, en);
        end
    end
    assign dout = {b, a};
endmodule

`endif
