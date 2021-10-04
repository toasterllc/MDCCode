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
    wire[WidthHalf:0] asub = a - {WidthHalf{'1}};
    wire[WidthHalf:0] ax = (!`LeftBit(asub,0) ? asub : a);
    reg[WidthHalf:0] a = 0;
    
    wire[WidthHalf:0] bsub = b - {WidthHalf{'1}};
    wire[WidthHalf:0] bx = (!`LeftBit(bsub,0) ? bsub : b);
    reg[WidthHalf:0] b = 0;
    
    reg enprev = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
            enprev <= 0;
        
        end else begin
            enprev <= en;
            
            if (en) begin
                a <= ax + din;
            end
            
            if (enprev) begin
                b <= bx + ax;
            end
            
            // $display("[FletcherChecksum]\t\t b:%h \t bx:%h \t a:%h \t ax:%h \t din:%h \t\t rst:%h en:%h [checksum: %h]",
            //     b,
            //     bx,
            //     a,
            //     ax,
            //     din, rst, en, dout);
        end
    end
    assign dout = {bx[WidthHalf-1:0], ax[WidthHalf-1:0]};
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
