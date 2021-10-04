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
    reg[WidthHalf+1:0] a = 0;
    reg[WidthHalf:0] asub = 0;
    reg[WidthHalf+1:0] afinal1 = 0;
    reg[WidthHalf+1:0] afinal2 = 0;
    wire[WidthHalf+1:0] afinalx = (!`LeftBit(afinal1,0) ? afinal1 : afinal2);
    
    // reg[WidthHalf:0] b1 = 0;
    // reg[WidthHalf:0] b2 = 0;
    // wire[WidthHalf:0] bx = (!`LeftBit(b1,0) ? b1 : b2);
    
    reg enprev = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            asub <= 0;
            enprev <= 0;
        
        end else begin
            enprev <= en;
            
            if (en) begin
                a <= a + din - asub;
                asub <= `LeftBit(a,0) ? {{WidthHalf{'1}},1'b0} : 0;
            end
            
            afinal1 <= a - {WidthHalf{'1}};
            afinal2 <= a;
            
            // if (enprev) begin
            //     b1 <= bx + ax - {WidthHalf{'1}};
            //     b2 <= bx + ax;
            // end
            
            $display("[FletcherChecksum]\t\t a:%h \t asub:%h \t afinal1:%h \t afinal2:%h \t din:%h \t\t rst:%h en:%h [checksum: %h]",
                a,
                asub,
                afinal1,
                afinal2,
                din, rst, en, dout);
        end
    end
    assign dout = {{WidthHalf{1'b0}}, afinalx[WidthHalf-1:0]};
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
