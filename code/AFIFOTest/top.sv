`timescale 1ns/1ps
`include "../GrayCode.v"

module AFIFO(
    input logic wclk,
    input logic w,
    input logic[Width-1:0] wd,
    output logic wfull,
    
    input logic rclk,
    input logic r,
    output logic[Width-1:0] rd,
    output logic rempty
);
    parameter Width = 12;
    parameter Size = 4; // Must be a power of 2
    localparam N = $clog2(Size)-1;
    
    logic[Width-1:0] mem[Size-1:0];
    logic[N:0] rbaddr, rgaddr; // Read addresses (binary, gray)
    logic[N:0] wbaddr, wgaddr; // Write addresses (binary, gray)
    
    // ====================
    // Read handling
    // ====================
    wire[N:0] rbaddrNext = rbaddr+1'b1;
    always @(posedge rclk)
        if (r & !rempty) begin
            rbaddr <= rbaddrNext;
            rgaddr <= (rbaddrNext>>1)^rbaddrNext;
        end
    
    logic rempty2;
    always @(posedge rclk, posedge aempty)
        if (aempty) {rempty, rempty2} <= 2'b11;
        else {rempty, rempty2} <= {rempty2, 1'b0};
    
    assign rd = mem[rbaddr];
    
    // ====================
    // Write handling
    // ====================
    wire[N:0] wbaddrNext = wbaddr+1'b1;
    always @(posedge wclk)
        if (w & !wfull) begin
            mem[wbaddr] <= wd;
            wbaddr <= wbaddrNext;
            wgaddr <= (wbaddrNext>>1)^wbaddrNext;
        end
    
    logic wfull2;
    always @(posedge wclk, posedge afull)
        if (afull) {wfull, wfull2} <= 2'b11;
        else {wfull, wfull2} <= {wfull2, 1'b0};
    
    // ====================
    // Async signal generation
    // ====================
    logic dir;
    wire aempty = (rgaddr==wgaddr) & !dir;
    wire afull = (rgaddr==wgaddr) & dir;
    wire dirset = (wgaddr[N]^rgaddr[N-1]) & ~(wgaddr[N-1]^rgaddr[N]);
    wire dirclr = ~(wgaddr[N]^rgaddr[N-1]) & (wgaddr[N-1]^rgaddr[N]);
    always @(posedge dirset, posedge dirclr)
        if (dirset) dir <= 1'b1;
        else dir <= 1'b0;
    
    initial begin
        wfull = 0;
        wfull2 = 0;
        // logic[Width-1:0] rd
        // rempty
        // rempty2
        for (int i=0; i<Size; i++)
            mem[i] = 0;
        
        rbaddr = 0;
        rgaddr = 0;
        wbaddr = 0;
        wgaddr = 0;
        dir = 0;
    end
endmodule

// module AFIFOTest(
//     input logic         pix_clk,    // Clock from image sensor
//     input logic         pix_frameValid,
//     input logic         pix_lineValid,
//     input logic[11:0]   pix_d,      // Data from image sensor
//
//     input logic         clk, // Clock from pll
//     output logic[11:0]  q,
//     output logic        qValid
// );
//     // AFIFO afifo(
//     //     .wclk(pix_clk),
//     //     .w(pix_frameValid & pix_lineValid),
//     //     .wd(pix_d),
//     //     .rclk(clk),
//     //     .r(!(pix_frameValid & pix_lineValid)),
//     //     .rd(q),
//     //     .rdValid(qValid)
//     // );
// endmodule

`ifdef SIM

module AFIFOTestSim();
    logic wclk;
    logic w;
    logic[11:0] wd;
    logic wfull;
    logic rclk;
    logic r;
    logic[11:0] rd;
    logic rempty;
    
    AFIFO afifo(.*);
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, AFIFOTestSim);

        wclk = 0;
        w = 0;
        wd = 0;
        rclk = 0;
        r = 0;
        
        w = 1;
        wd = 8'hA;
        #1; wclk = 1;
        #1; wclk = 0;
        w = 0;
        $display("wrote byte, wfull: %d", wfull);
        
        w = 1;
        wd = 8'hB;
        #1; wclk = 1;
        #1; wclk = 0;
        w = 0; 
        $display("wrote byte, wfull: %d", wfull);
        
        w = 1;
        wd = 8'hC;
        #1; wclk = 1;
        #1; wclk = 0;
        w = 0;
        $display("wrote byte, wfull: %d", wfull);
        
        w = 1;
        wd = 8'hD;
        #1; wclk = 1;
        #1; wclk = 0;
        w = 0;
        $display("wrote byte, wfull: %d", wfull);
        
        // w = 1;
        // wd = 8'hD;
        // #1; clk = 1;
        // #1; clk = 0;
        // w = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;
        
        $display("read byte: %h (rempty: %d)", rd, rempty);
        r = 1;
        #1; rclk = 1;
        #1; rclk = 0;
        r = 0;



        #10000000;
        //        #200000000;
        //        #2300000000;
        $finish;
    end
endmodule

`endif
