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
    reg[1023:0] crc_din = {1024{1'b1}};
    wire[15:0] crc_dout;
    CRC16 crc(
        .clk(clk),
        .rst_(crc_rst_),
        .din(crc_din[1023]),
        .dout(crc_dout),
        .doutNext()
    );
    
    
    initial begin
        #1000;
        wait(!clk);
        crc_rst_ = 1;
        
        repeat (1024) begin
            wait(clk);
            wait(!clk);
            crc_din = crc_din<<1;
            
            $display("CRC: %h", crc_dout);
        end
        
        #1000;
        $finish;
    end
endmodule
