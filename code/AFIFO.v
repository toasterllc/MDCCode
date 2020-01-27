// Based on Clifford E. Cummings paper:
//   http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf
module AFIFO(
    input wire rclk,
    input wire r,
    output wire[Width-1:0] rd,
    output reg rempty,
    
    input wire wclk,
    input wire w,
    input wire[Width-1:0] wd,
    output reg wfull = 0
);
    parameter Width = 12;
    parameter Size = 4; // Must be a power of 2 and >=4
    localparam N = $clog2(Size)-1;
    
    reg[Width-1:0] mem[Size-1:0];
    reg[N:0] rbaddr=0, rgaddr=0; // Read addresses (binary, gray)
    reg[N:0] wbaddr=0, wgaddr=0; // Write addresses (binary, gray)
    
    // ====================
    // Read handling
    // ====================
    wire[N:0] rbaddrNext = rbaddr+1'b1;
    always @(posedge rclk)
        if (r & !rempty) begin
            rbaddr <= rbaddrNext;
            rgaddr <= (rbaddrNext>>1)^rbaddrNext;
        end
    
    reg rempty2 = 0;
    always @(posedge rclk, posedge aempty)
        // TODO: ensure that before the first clock, empty==true so outside entities don't think they can read
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
    
    reg wfull2 = 0;
    always @(posedge wclk, posedge afull)
        if (afull) {wfull, wfull2} <= 2'b11;
        else {wfull, wfull2} <= {wfull2, 1'b0};
    
    // ====================
    // Async signal generation
    // ====================
    reg dir = 0;
    wire aempty = (rgaddr==wgaddr) & !dir;
    wire afull = (rgaddr==wgaddr) & dir;
    wire dirclr = (rgaddr[N]!=wgaddr[N-1]) & (rgaddr[N-1]==wgaddr[N]);
    wire dirset = (rgaddr[N]==wgaddr[N-1]) & (rgaddr[N-1]!=wgaddr[N]);
    always @(posedge dirclr, posedge dirset)
        if (dirclr) dir <= 0;
        else dir <= 1;
endmodule
