`timescale 1ns/1ps
`include "../GrayCode.v"

module AFIFO(
    input logic wclk,
    input logic w,
    input logic[Width-1:0] wd,
    
    input logic rclk,
    input logic r,
    output logic[Width-1:0] rd,
    output logic rdValid
);
    parameter Width = 12;
    parameter Size = 4; // Must be a power of 2
    parameter AddrWidth = $clog2(Size);
    
    logic[Width-1:0] mem[Size-1:0];
    
    logic[AddrWidth-1:0] waddrGray;
    logic[AddrWidth-1:0] waddrGrayNext;
    Bin2Gray #(.Width(AddrWidth)) x0(.d(waddr+1), .q(waddrGrayNext));
    logic[AddrWidth-1:0] waddr;
    Gray2Bin #(.Width(AddrWidth)) x1(.d(waddrGray), .q(waddr));
    
    logic[AddrWidth-1:0] raddrGray;
    logic[AddrWidth-1:0] raddrGrayNext;
    Bin2Gray #(.Width(AddrWidth)) x2(.d(raddr+1), .q(raddrGrayNext));
    logic[AddrWidth-1:0] raddr;
    Gray2Bin #(.Width(AddrWidth)) x3(.d(raddrGray), .q(raddr));
    
    // logic empty;
    // assign empty = ;
    
    // // Read domain
    // logic r_empty;
    // // assign r_empty = (rpos==wpos);
    //
    // // Write domain
    // logic w_full;
    // // assign w_full = ;
    
    always @(posedge wclk) begin
        if (w) begin
            mem[waddr] <= wd;
            waddrGray <= waddrGrayNext;
        end
    end
    
    always @(posedge rclk) begin
        if (r) begin
            raddrGray <= raddrGrayNext;
        end
    end
    
    assign rd = mem[raddr];
    assign rdValid = !r_empty;
endmodule

module AFIFOTest(
    input logic         pix_clk,    // Clock from image sensor
    input logic         pix_frameValid,
    input logic         pix_lineValid,
    input logic[11:0]   pix_d,      // Data from image sensor
    
    input logic         clk, // Clock from pll
    output logic[11:0]  q,
    output logic        qValid
);
    AFIFO afifo(
        .wclk(pix_clk),
        .w(pix_frameValid & pix_lineValid),
        .wd(pix_d),
        .rclk(clk),
        .r(!(pix_frameValid & pix_lineValid)),
        .rd(q),
        .rdValid(qValid)
    );
endmodule

`ifdef SIM







module AFIFOTestSim(
);
    input logic         pix_clk;
    input logic         pix_frameValid;
    input logic         pix_lineValid;
    input logic[11:0]   pix_d;
    
    input logic         clk;
    output logic[11:0]  q;
    output logic        qValid;
    
    AFIFOTest afifotest(
        .pix_clk(pix_clk),
        .pix_frameValid(pix_frameValid),
        .pix_lineValid(pix_lineValid),
        .pix_d(pix_d),
        .clk(clk),
        .q(q),
        .qValid(qValid)
    );
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, AFIFOTestSim);
       
       #10000000;
       $finish;
    end
endmodule

`endif
