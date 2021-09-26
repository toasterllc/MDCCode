`include "Util.v"
`timescale 1ns/1ps

module SwapEndianness #(
    parameter Width = 32
)(
    input wire[Width-1:0]   din,
    output wire[Width-1:0]  dout
);
    genvar i;
    for (i=0; i<Width/2; i=i+8) begin
        assign `RightBits(dout,i,8) = `LeftBits(din,i,8);
        assign `LeftBits(dout,i,8)  = `RightBits(din,i,8);
    end
endmodule

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
    reg[WidthHalf-1:0]  a = 0;
    reg[WidthHalf-1:0]  b = 0;
    wire[WidthHalf-1:0] an = ({1'b0,a} + din) % {WidthHalf{'1}};
    wire[WidthHalf-1:0] bn = ({1'b0,b} + an)  % {WidthHalf{'1}};
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
        
        end else if (en) begin
            a <= an;
            b <= bn;
        end
    end
    assign dout[Width-1:WidthHalf]  = b;
    assign dout[WidthHalf-1:0]      = a;
endmodule

module Testbench();
    localparam ChecksumWidth = 64;
    localparam ChecksumWidthHalf = ChecksumWidth/2;
    
    reg                         clk     = 0;
    reg                         rst     = 0;
    reg                         en      = 0;
    wire[ChecksumWidthHalf-1:0] din;
    wire[ChecksumWidth-1:0]     dout;
    
    FletcherChecksum #(
        .Width(ChecksumWidth)
    ) FletcherChecksum(
        .clk    (clk    ),
        .rst    (rst    ),
        .en     (en     ),
        .din    (din    ),
        .dout   (dout   )
    );
    
    reg[63:0] data = 64'h6162636465666768; // abcdefgh
    reg[31:0] i = 0;
    reg[31:0] ii = 0;
    
    SwapEndianness #(
        .Width(ChecksumWidthHalf)
    ) SwapEndianness(
        .din(`LeftBits(data,0,ChecksumWidthHalf)),
        .dout(din)
    );
    
    initial begin
        en = 1;
        #1;
        
        for (i=0; i<($size(data)/ChecksumWidthHalf); i++) begin
            clk = 1;
            #1
            clk = 0;
            #1;
            
            data = data<<ChecksumWidthHalf;
            #1;
            
            $display("%h", dout);
        end
        
        $finish;
    end
endmodule
