`include "../Util/CRC7.v"

`timescale 1ns/1ps

module Top();
    reg clk = 0;
    
    initial begin
        $dumpfile("top.vcd");
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
    
    reg crc_en = 0;
    reg[127:0] crc_din = 136'b00111111000000110101001101000100010100110101001000110001001100100011100010000000100010111011011110011101011001100000000101000110;
    wire[15:0] crc_dout;
    CRC7 crc(
        .clk(clk),
        .en(crc_en),
        .din(crc_din[$size(crc_din)-1])
    );
    
    
    initial begin
        reg[7:0] i;
        
        #1000;
        wait(!clk);
        crc_en = 1;
        
        repeat (128) begin
            wait(clk);
            wait(!clk);
            crc_din = crc_din<<1;
            
            $display("CRC: %h", crc.d);
        end
        
        #1000;
        $finish;
    end
endmodule
