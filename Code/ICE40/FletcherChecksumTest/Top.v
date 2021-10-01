`include "Util.v"
`include "FletcherChecksum.v"
`timescale 1ns/1ps

`ifdef SIM

module Testbench();
    localparam ChecksumWidth16 = 16;
    localparam ChecksumWidth32 = 32;
    localparam ChecksumWidth64 = 64;
    
    localparam ChecksumWidthHalf16 = ChecksumWidth16/2;
    localparam ChecksumWidthHalf32 = ChecksumWidth32/2;
    localparam ChecksumWidthHalf64 = ChecksumWidth64/2;
    
    reg     clk16   = 0;
    reg     clk32   = 0;
    reg     clk64   = 0;
    
    reg     rst     = 0;
    wire    rst16   = rst;
    wire    rst32   = rst;
    wire    rst64   = rst;
    
    reg     en16    = 0;
    reg     en32    = 0;
    reg     en64    = 0;
    
    reg[ChecksumWidthHalf16-1:0] din16 = 0;
    reg[ChecksumWidthHalf32-1:0] din32 = 0;
    reg[ChecksumWidthHalf64-1:0] din64 = 0;
    
    wire[ChecksumWidth16-1:0] dout16;
    wire[ChecksumWidth32-1:0] dout32;
    wire[ChecksumWidth64-1:0] dout64;
    
    wire[ChecksumWidth16-1:0] doutCorrect16;
    wire[ChecksumWidth32-1:0] doutCorrect32;
    wire[ChecksumWidth64-1:0] doutCorrect64;
    
    FletcherChecksum #(
        .Width(16)
    ) FletcherChecksum16(
        .clk    (clk16  ),
        .rst    (rst16  ),
        .en     (en16   ),
        .din    (din16  ),
        .dout   (dout16 )
    );
   
    FletcherChecksum #(
        .Width(32)
    ) FletcherChecksum32(
        .clk    (clk32  ),
        .rst    (rst32  ),
        .en     (en32   ),
        .din    (din32  ),
        .dout   (dout32 )
    );

    FletcherChecksum #(
        .Width(64)
    ) FletcherChecksum64(
        .clk    (clk64  ),
        .rst    (rst64  ),
        .en     (en64   ),
        .din    (din64  ),
        .dout   (dout64 )
    );

    FletcherChecksumCorrect #(
        .Width(16)
    ) FletcherChecksumCorrect16(
        .clk    (clk16  ),
        .rst    (rst16  ),
        .en     (en16   ),
        .din    (din16  ),
        .dout   (doutCorrect16 )
    );

    FletcherChecksumCorrect #(
        .Width(32)
    ) FletcherChecksumCorrect32(
        .clk    (clk32  ),
        .rst    (rst32  ),
        .en     (en32   ),
        .din    (din32  ),
        .dout   (doutCorrect32 )
    );

    FletcherChecksumCorrect #(
        .Width(64)
    ) FletcherChecksumCorrect64(
        .clk    (clk64  ),
        .rst    (rst64  ),
        .en     (en64   ),
        .din    (din64  ),
        .dout   (doutCorrect64 )
    );
    
    reg[32768-1:0] data = 0;
    reg[31:0] len = 0;
    // reg[128-1:0] data = 128'h6162636465666768_6162636465666768; // abcdefgh_abcdefgh
    // reg[128-1:0] data = 128'hFFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF; // abcdefgh_abcdefgh
    // reg[128-1:0] data = 128'hFEFEFEFEFEFEFEFE_FEFEFEFEFEFEFEFE;
    reg[31:0] i = 0;
    reg[31:0] ii = 0;
    
    task Clk16; begin
        clk16 = 1;
        #1;
        clk16 = 0;
        #1;
    end endtask
    
    task Clk32; begin
        clk32 = 1;
        #1;
        clk32 = 0;
        #1;
    end endtask
    
    task Clk64; begin
        clk64 = 1;
        #1;
        clk64 = 0;
        #1;
    end endtask
    
    initial begin
        forever begin
            // Generate random data length
            len = ($urandom % ($size(data)/8))+1;
            
            // Fill `data` with random data
            data = 0;
            for (i=0; i<(len+3)/4; i++) begin
                `RightBits(data,i*32,32) = $urandom;
            end
            
            // $display(data);
            // `Finish;
            
            // `RightBits(data,0*8,8) = 8'h61;
            // `RightBits(data,1*8,8) = 8'h62;
            // `RightBits(data,2*8,8) = 8'h63;
            // `RightBits(data,3*8,8) = 8'h64;
            // `RightBits(data,4*8,8) = 8'h65;
            // `RightBits(data,5*8,8) = 8'h66;
            // `RightBits(data,6*8,8) = 8'h67;
            // `RightBits(data,7*8,8) = 8'h68;
            // len = 8;
            
            // `RightBits(data,0*8,8) = 8'hb0;
            // `RightBits(data,1*8,8) = 8'h6a;
            // `RightBits(data,2*8,8) = 8'h6a;
            // `RightBits(data,3*8,8) = 8'h58;
            // `RightBits(data,4*8,8) = 8'h3c;
            // `RightBits(data,5*8,8) = 8'h87;
            // `RightBits(data,6*8,8) = 8'h1c;
            // `RightBits(data,7*8,8) = 8'h9e;
            // len = 8;
            
            
            // `RightBits(data,0*8,8) = 8'hd3;
            // `RightBits(data,1*8,8) = 8'h1d;
            // `RightBits(data,2*8,8) = 8'he3;
            // `RightBits(data,3*8,8) = 8'he9;
            // `RightBits(data,4*8,8) = 8'hdc;
            // `RightBits(data,5*8,8) = 8'hdf;
            // `RightBits(data,6*8,8) = 8'h53;
            // `RightBits(data,7*8,8) = 8'hee;
            // len = 8;

            // `RightBits(data,0*8,8) = 8'h17;
            // `RightBits(data,1*8,8) = 8'h02;
            // `RightBits(data,2*8,8) = 8'hf5;
            // `RightBits(data,3*8,8) = 8'h0b;
            // `RightBits(data,4*8,8) = 8'h0a;
            // `RightBits(data,5*8,8) = 8'h96;
            // `RightBits(data,6*8,8) = 8'h3a;
            // `RightBits(data,7*8,8) = 8'h05;
            // len = 8;
            
            // len = 8;
            
            // Reset checksums
            rst = 1;
            #1;
            Clk16();
            Clk32();
            Clk64();
            rst = 0;
            #1;
            
            // Fletcher-16
            begin
                en16 = 1;
                #1;
                for (i=0; i<len; i++) begin
                    din16 = `RightBits(data,i*ChecksumWidthHalf16,ChecksumWidthHalf16);
                    #1;
                    Clk16();
                end
                en16 = 0;
                #1;
                for (i=0; i<2; i++) Clk16();

                if (dout16 == doutCorrect16) begin
                    $display("checksum: %h [expected: %h] [len:%0d] ✅", dout16, doutCorrect16, len);
                end else begin
                    $display("checksum: %h [expected: %h] [len:%0d] ❌", dout16, doutCorrect16, len);
                    `Finish;
                end
            end
            `Finish;
            
            // // Fletcher-32
            // begin
            //     en32 = 1;
            //     #1;
            //     for (i=0; i<(len+1)/2; i++) begin
            //         din32 = `RightBits(data,i*ChecksumWidthHalf32,ChecksumWidthHalf32);
            //         #1;
            //         Clk32();
            //     end
            //     en32 = 0;
            //     #1;
            //     for (i=0; i<2; i++) Clk32();
            //
            //     if (dout32 == doutCorrect32) begin
            //         $display("checksum: %h [expected: %h] [len:%0d] ✅", dout32, doutCorrect32, len);
            //     end else begin
            //         $display("checksum: %h [expected: %h] [len:%0d] ❌", dout32, doutCorrect32, len);
            //         `Finish;
            //     end
            // end
            // // `Finish;
            //
            // // Fletcher-64
            // begin
            //     en64 = 1;
            //     #1;
            //     for (i=0; i<(len+3)/4; i++) begin
            //         din64 = `RightBits(data,i*ChecksumWidthHalf64,ChecksumWidthHalf64);
            //         #1;
            //         Clk64();
            //     end
            //     en64 = 0;
            //     #1;
            //     for (i=0; i<2; i++) Clk64();
            //
            //     if (dout64 == doutCorrect64) begin
            //         $display("checksum: %h [expected: %h] [len:%0d] ✅", dout64, doutCorrect64, len);
            //     end else begin
            //         $display("checksum: %h [expected: %h] [len:%0d] ❌", dout64, doutCorrect64, len);
            //         `Finish;
            //     end
            // end
            // // `Finish;
        end
        
        // for (i=0; i<($size(data)/ChecksumWidthHalf)+4; i++) begin
        //     $display("data: %h", data);
        //
        //
        //     clk = 1;
        //     #1
        //     clk = 0;
        //     #1;
        //
        //     // We fill `data` with a 'weird' value (0x41), and not with 00/FF, because the
        //     // checksum is unaffected by these latter values. So we use a 'weird' value
        //     // that definitely affects the checksum, to make sure that at the time that
        //     // we read the checksum output, the algorithm hasn't been accidentally peeking
        //     // ahead.
        //     data = (data<<ChecksumWidthHalf) | {(ChecksumWidthHalf/8){8'h41}};
        //     if (i === 8-1) en = 0;
        //     // data = (data<<ChecksumWidthHalf) | {ChecksumWidthHalf{'1}};
        //     #1;
        //
        //     $display("checksum:\t\t\t %h\t\t\t %h   [%h]\n", `LeftBits(checksum,0,ChecksumWidthHalf), `RightBits(checksum,0,ChecksumWidthHalf), checksum);
        //     // $display("checksum: %h\n", dout);
        // end
        
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
