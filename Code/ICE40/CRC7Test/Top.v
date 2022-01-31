`include "CRC7.v"

`timescale 1ns/1ps

module Top();
    reg clk = 0;
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        forever begin
            clk = 0;
            #42;
            clk = 1;
            #42;
        end
    end
    
    reg crc_rst = 0;
    reg crc_en = 0;
    // reg[135:0] crc_din = 136'h3f0353445352313238808bb79d66014677;
    // reg[135:0] crc_din = 136'h3f400e0032db790003b8ab7f800a40405f;
    
    // reg[135:0] crc_din = 136'h00_F353445352313238808bb79d660146_01;
    // reg[135:0] crc_din = 136'h00_7ffe0032db790003b8ab7f800a4040_71;
    
    // reg[135:0] crc_din = 136'h00_f353445352313238808bb79d660146_01;
    reg[135:0] crc_din = 136'h00_7ffe0032db790003b8ab7f800a4040_79;
    
    
    // reg[47:0] crc_din = 48'h03aaaa0520d1;
    // reg[47:0] crc_din = 48'h0600000900dd;
    // reg[47:0] crc_din = 48'h070000070075;
    // reg[47:0] crc_din = 48'h08000001aa13;
    // reg[47:0] crc_din = 48'h0B0000070081;
    
    CRC7 crc(
        .clk(clk),
        .rst(crc_rst),
        .en(crc_en),
        .din(crc_din[$size(crc_din)-1])
    );
    
    
    initial begin
        reg[7:0] i;
        
        #1000;
        wait(!clk);
        
        crc_en = 0;
        
        crc_rst = 1;
        wait(clk);
        wait(!clk);
        crc_rst = 0;
        wait(clk);
        wait(!clk);
        
        crc_en = 1;
        
        
        
        repeat ($size(crc_din)-8) begin
            wait(clk);
            wait(!clk);
            $display("CRC: %h", {crc.d, 1'b1}); // Printing in the format that allows comparison to the last byte of the raw SD byte stream
            crc_din = crc_din<<1;
        end
        
        #1000;
        $finish;
    end
endmodule
