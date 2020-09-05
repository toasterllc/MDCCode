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
    reg[511:0] crc_din = 512'hFF0FFF00_FFCCC3CC_C33CCCFF_FEFFFEEF_FFDFFFDD_FFFBFFFB_BFFF7FFF_77F7BDEF_FFF0FFF0_0FFCCC3C_CC33CCCF_FFEFFFEE_FFFDFFFD_DFFFBFFF_BBFFF7FF_F77F7BDE;
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
        
        repeat (128) begin
            wait(clk);
            wait(!clk);
            crc_din = crc_din<<4;
            
            $display("CRC: %h", crc_dout);
        end
        
        #1000;
        $finish;
    end
endmodule
