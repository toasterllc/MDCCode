`ifndef ImgSim_v
`define ImgSim_v

`timescale 1ps/1ps

module ImgSim #(
    parameter ImageWidth = 256,
    parameter ImageHeight = 256
)(
    output wire         img_dclk,
    output reg[11:0]    img_d = 0,
    output reg          img_fv = 0,
    output reg          img_lv = 0,
    input wire          img_rst_
);
    reg clk = 0;
    initial forever begin
        #5102; // 98 MHz
        clk = !clk;
    end
    
    assign img_dclk = (!img_rst_ ? 0 : clk);
    
    initial forever begin
        reg[31:0] i;
        reg[31:0] row;
        reg[31:0] col;
        reg[31:0] pxCount;
        
        // Wait 16 cycles before starting the next frame
        img_fv = 0;
        for (i=0; i<16; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
        
        // img_fv=1 (frame start)
        // Wait 16 cycles before starting the first row
        img_fv = 1;
        for (i=0; i<16; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
        
        pxCount = 0;
        for (row=0; row<ImageHeight; row=row+1) begin
            // $display("[ImgSim] Row %0d", row);
            // img_lv=1 (line start)
            // Output a row
            img_lv = 1;
            for (col=0; col<ImageWidth; col=col+1) begin
                img_d = pxCount;
                pxCount = pxCount+1;
                
                // Test histogram
                if (!(row%4) && !(col%4)) begin
                    img_d = 12'hFFF; // Highlight
                end else begin
                    img_d = 12'h000; // Shadow
                end
                wait(clk);
                wait(!clk);
            end
            
            // img_lv=0 (line end)
            // Wait 16 cycles before continuing to the next row
            img_lv = 0;
            for (i=0; i<16; i=i+1) begin
                wait(clk);
                wait(!clk);
            end
        end
        
        // img_fv=0 (frame end)
        // Wait 16 cycles before continuing to the next frame
        img_fv = 0;
        for (i=0; i<16; i=i+1) begin
            wait(clk);
            wait(!clk);
        end
    end

endmodule

`endif
