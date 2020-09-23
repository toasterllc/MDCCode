`timescale 1ns/1ps

module CRC16(
    input wire clk,
    input wire rst_,
    input din,
    output wire[15:0] dout,
    output wire[15:0] doutNext
);
    reg[15:0] d = 0;
    wire dx = din^d[15];
    wire[15:0] dnext = { d[14], d[13], d[12], d[11]^dx, d[10], d[9], d[8], d[7], d[6], d[5], d[4]^dx, d[3], d[2], d[1], d[0], dx };
    always @(posedge clk)
        if (!rst_) d <= 0;
        else d <= dnext;
    assign dout = d;
    assign doutNext = dnext;
endmodule

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
    reg[4095:0] crc_din = ~0;
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
        
        repeat (1024) begin
            wait(clk);
            wait(!clk);
            crc_din = crc_din<<4;
            
            $display("CRC: %h", crc_dout);
        end
        
        #1000;
        $finish;
    end
endmodule
