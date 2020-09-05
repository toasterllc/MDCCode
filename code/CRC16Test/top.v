`include "../CRC16.v"

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
    
    reg crc_rst_ = 0;
    reg[7:0] crc_din = 0;
    wire[15:0] crc_dout;
    CRC16 crc(
        .clk(clk),
        .rst_(crc_rst_),
        .din(crc_din[$size(crc_din)-1]),
        .dout(crc_dout),
        .doutNext()
    );
    
    
    initial begin
        reg[7:0] i;
        
        #1000;
        wait(!clk);
        crc_rst_ = 1;
        
        for (i=0; i<128; i=i+1) begin
            $display("crc_din = %0d", i);
            crc_din = i;
            repeat (8) begin
                wait(clk);
                wait(!clk);
                crc_din = crc_din<<1;
                
                $display("CRC: %h", crc_dout);
            end
        end
        
        #1000;
        $finish;
    end
endmodule
