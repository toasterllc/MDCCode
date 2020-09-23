`include "../CRC16.v"

`timescale 1ns/1ps

module Top(
    input wire clk,
    input wire en,
    input wire din,
    output wire dout
);
    CRC16 #(
        .Delay(0)
    ) crc(
        .clk(clk),
        .en(en),
        .din(din),
        .dout(dout)
    );
endmodule


`ifdef SIM
module Testbench();
    reg clk = 0;
    reg en = 0;
    reg din = 0;
    wire dout;
    Top Top(
        .clk(clk),
        .en(en),
        .din(din),
        .dout(dout)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        forever begin
            clk = 0;
            #42;
            clk = 1;
            #42;
        end
    end
    
    initial begin
        reg[15:0] i;
        reg[15:0] crc;
        
        for (i=0; i<17; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
        
        en = 1;
        din = 1;
        for (i=0; i<1024; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
        
        en = 0;
        for (i=0; i<16; i=i+1) begin
            crc = (crc<<1)|dout;
            wait(clk);
            wait(!clk);
        end
        
        $display("crc: %x", crc);
    end
    
endmodule
`endif