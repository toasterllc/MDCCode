`ifndef PixSim_v
`define PixSim_v

`timescale 1ps/1ps

module PixSim #(
    parameter ImageWidth = 256,
    parameter ImageHeight = 256
)(
    output wire         pix_dclk,
    output reg[11:0]    pix_d = 0,
    output reg          pix_fv = 0,
    output reg          pix_lv = 0,
    input wire          pix_rst_
);
    reg clk = 0;
    initial forever begin
        #5102; // 98 MHz
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
            // $display("[PixSim] Row %0d", row);
            // pix_lv=1 (line start)
            // Output a row
            pix_lv = 1;
            for (col=0; col<ImageWidth; col=col+1) begin
                // Test histogram
                if (!(row%4) && !(col%4)) begin
                    pix_d = 12'hFFF; // Highlight
                end else begin
                    pix_d = 12'h000; // Shadow
                end
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
