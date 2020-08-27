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
    reg crc_din = 0;
    wire[15:0] crc_dout;
    CRC16 crc(
        .clk(clk),
        .rst_(crc_rst_),
        .din(crc_din),
        .dout(crc_dout),
        .doutNext()
    );
    
    
    initial begin
        #1000;
        wait(!clk);
        crc_rst_ = 1;
        crc_din = 1;
        wait(clk);
        
        repeat (1024) begin
            wait(!clk);
            $display("CRC: %h", crc_dout);
            wait(clk);
        end
        
        #1000;
        $finish;
    end
endmodule
