`include "Util.v"
`timescale 1ns/1ps

// function[31:0] SwapEndian32;
//     input[31:0] d;
//     begin
//         localparam Half = (32)/2;
//         reg[31:0] i;
//         for (i=0; i<Half; i+=8) begin
//             // assign `RightBits(SwapEndian32,i,8) = `LeftBits(d,i,8);
//             assign `LeftBits(SwapEndian32,i,8) = `RightBits(d,i,8);
//         end
//     end
// endfunction
//
// function[63:0] SwapEndian64;
//     input[63:0] d;
//     genvar i;
//     begin
//         localparam Half = (64)/2;
//         for (i=0; i<Half; i+=8) begin
//             assign `RightBits(SwapEndian64,i,8) = `LeftBits(d,i,8);
//             assign `LeftBits(SwapEndian64,i,8) = `RightBits(d,i,8);
//         end
//     end
// endfunction

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
    wire[WidthHalf-1:0] an = (a + {1'b0,din}) % {WidthHalf{'1}};
    wire[WidthHalf-1:0] bn = (b + {1'b0,an}) % {WidthHalf{'1}};
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
    localparam ChecksumWidth = 16;
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
    
    // assign data_swapped = {<<8{data}};
    
    // reg[47:0] data = 48'h61_62_63_64_65_66; // abcdef
    // reg[47:0] data = 48'h6261_6463_6665; // ba_dc_fe
    // reg[63:0] data = 64'h64636261_00006665; // dcba_00fe
    
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
