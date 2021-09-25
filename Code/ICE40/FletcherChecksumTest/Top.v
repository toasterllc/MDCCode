`include "Util.v"
`timescale 1ns/1ps

module Fletcher32(
    input wire          clk,
    input wire          rst,
    input wire          en,
    input wire[15:0]    din,
    output wire[31:0]   dout
);
    reg[15:0] a = 0;
    reg[15:0] b = 0;
    wire[31:0] an = (a + din) % 16'hFFFF;
    wire[31:0] bn = (b + an) % 16'hFFFF;
    always @(posedge clk) begin
        if (rst) begin
            a <= 0;
            b <= 0;
        
        end else if (en) begin
            a <= an;
            b <= bn;
        end
    end
    assign dout[31:16]  = b;
    assign dout[15:0]   = a;
endmodule

module Testbench();
    reg         clk     = 0;
    reg         rst     = 0;
    reg         en      = 0;
    reg[15:0]   din     = 0;
    wire[31:0]  dout;
    
    Fletcher32 Fletcher32(
        .clk    (clk    ),
        .rst    (rst    ),
        .en     (en     ),
        .din    (din    ),
        .dout   (dout   )
    );
    
    // reg[47:0] data = 48'h61_62_63_64_65_66; // ab_cd_ef
    reg[47:0] data = 48'h6261_6463_6665; // ba_dc_fe
    reg[31:0] i = 0;
    initial begin
        en = 1;
        #1;
        
        for (i=0; i<3; i++) begin
            din = `LeftBits(data,0,16);
            data = data<<16;
            #1;
            
            clk = 1;
            #1
            clk = 0;
            #1
            
            $display("  din: %h", din);
            $display("%h", dout);
        end
        
        $finish;
    end
endmodule
