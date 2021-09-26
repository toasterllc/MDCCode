`include "Util.v"
`include "FletcherChecksum.v"
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

`ifdef SIM

module Testbench();
    localparam ChecksumWidth = 32;
    localparam ChecksumWidthHalf = ChecksumWidth/2;
    
    wire[ChecksumWidth-1:0] ExpectedChecksum;
    case (ChecksumWidth)
    16: assign ExpectedChecksum = 16'h0627;
    32: assign ExpectedChecksum = 32'hebe19591;
    64: assign ExpectedChecksum = 64'h312E2B28CCCAC8C6;
    endcase
    
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
    // reg[128-1:0] data = 128'h6162636465666768_6162636465666768; // abcdefgh_abcdefgh
    // reg[128-1:0] data = 128'hFFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF; // abcdefgh_abcdefgh
    // reg[128-1:0] data = 128'hFEFEFEFEFEFEFEFE_FEFEFEFEFEFEFEFE;
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
        
        for (i=0; i<($size(data)/ChecksumWidthHalf)+30; i++) begin
            $display("data: %h", data);
            
            clk = 1;
            #1
            clk = 0;
            #1;
            
            // We fill `data` with a 'weird' value (0x41), and not with 00/FF, because the
            // checksum is unaffected by these latter values. So we use a 'weird' value
            // that definitely affects the checksum, to make sure that at the time that
            // we read the checksum output, the algorithm hasn't been accidentally peeking
            // ahead.
            data = (data<<ChecksumWidthHalf) | {(ChecksumWidthHalf/8){8'h00}};
            if (i === 4) en = 0;
            // data = (data<<ChecksumWidthHalf) | {ChecksumWidthHalf{'1}};
            #1;
            
            if (dout===ExpectedChecksum)    $display("checksum: %h ✅\n", dout);
            else                            $display("checksum: %h ❌\n", dout);
        end
        
        $finish;
    end
endmodule

`else

module Top(
    input wire rst_,
    
    output wire prop_w_ready, // Whether half of the FIFO can be written
    output wire prop_r_ready, // Whether half of the FIFO can be read
    
    input wire w_clk,
    input wire w_trigger,
    input wire[15:0] w_data,
    output wire w_ready,
    
    input wire r_clk,
    input wire r_trigger,
    output wire[31:0] r_data,
    output wire r_ready
);
    
    FletcherChecksum #(
        .Width(32)
    ) FletcherChecksum(
        .clk    (w_clk),
        .rst    (rst_),
        .en     (w_trigger),
        .din    (w_data),
        .dout   (r_data)
    );
    
endmodule

`endif
