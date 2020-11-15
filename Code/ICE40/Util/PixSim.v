`ifndef PixSim_v
`define PixSim_v

`timescale 1ns/1ps

module PixSim(
    output wire         pix_dclk,
    output reg[11:0]    pix_d = 0,
    output reg          pix_fv = 0,
    output reg          pix_lv = 0,
    input wire          pix_rst_
);
    localparam ImageWidth = 2304;
    localparam ImageHeight = 1296;
    
    reg clk = 0;
    initial forever begin
        #5;
        clk = !clk;
    end
    
    assign pix_dclk = (!pix_rst_ ? 0 : clk);
    
    initial forever begin
        reg[31:0] i;
        reg[31:0] row;
        reg[31:0] col;
        
        // Wait 16 cycles before starting the next frame
        pix_fv = 0;
        for (i=0; i<16; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
        
        // pix_fv=1 (frame start)
        // Wait 16 cycles before starting the first row
        pix_fv = 1;
        for (i=0; i<16; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
        
        for (row=0; row<ImageHeight; row=row+1) begin
            // pix_lv=1 (line start)
            // Output a row
            pix_lv = 1;
            for (col=0; col<ImageWidth; col=col+1) begin
                pix_d = row;
                wait(clk);
                wait(!clk);
            end
            
            // pix_lv=0 (line end)
            // Wait 16 cycles before continuing to the next row
            pix_lv = 0;
            for (i=0; i<16; i=i+1) begin
                wait(clk);
                wait(!clk);
            end
        end
        
        // pix_fv=0 (frame end)
        // Wait 16 cycles before continuing to the next frame
        pix_fv = 0;
        for (i=0; i<16; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
    end

endmodule

`endif
