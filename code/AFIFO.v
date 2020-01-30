// Based on Clifford E. Cummings paper:
//   http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf
module AFIFO #(
    parameter Width=12,
    parameter Size=4 // Must be a power of 2 and >=4
)(
    input wire rclk,            // Read clock
    input wire r,               // Read trigger
    output wire[Width-1:0] rd,  // Read data
    output wire rok,            // Read OK (data available -- not empty)
    
    input wire wclk,            // Write clock
    input wire w,               // Write trigger
    input wire[Width-1:0] wd,   // Write data
    output wire wok             // Write OK (space available -- not full)
);
    localparam N = $clog2(Size)-1;
    reg[Width-1:0] mem[Size-1:0];
    
    //          /* synthesis syn_ramstyle="registers" */
    
    // ====================
    // Read handling
    // ====================
    reg[N:0] rbaddr, rgaddr; // Read addresses (binary, gray)
    wire[N:0] rbaddrNext = rbaddr+1'b1;
    always @(posedge rclk)
        if (r & !rempty) begin
            rbaddr <= rbaddrNext;
            rgaddr <= (rbaddrNext>>1)^rbaddrNext;
        end
    
    reg rempty, rempty2;
    always @(posedge rclk, posedge aempty)
        // TODO: ensure that before the first clock, empty==true so outside entities don't think they can read
        if (aempty) {rempty, rempty2} <= 2'b11;
        else {rempty, rempty2} <= {rempty2, 1'b0};
    
    assign rd = mem[rbaddr];
    assign rok = !rempty;
    
    // ====================
    // Write handling
    // ====================
    reg[N:0] wbaddr, wgaddr; // Write addresses (binary, gray)
    wire[N:0] wbaddrNext = wbaddr+1'b1;
    always @(posedge wclk)
        if (w & !wfull) begin
            mem[wbaddr] <= wd;
            wbaddr <= wbaddrNext;
            wgaddr <= (wbaddrNext>>1)^wbaddrNext;
        end
    
    reg wfull, wfull2;
    always @(posedge wclk, posedge afull)
        if (afull) {wfull, wfull2} <= 2'b11;
        else {wfull, wfull2} <= {wfull2, 1'b0};
    
    assign wok = !wfull;
    
    // ====================
    // Async signal generation
    // ====================
    reg dir;
    wire aempty = (rgaddr==wgaddr) & !dir;
    wire afull = (rgaddr==wgaddr) & dir;
    wire dirclr = (rgaddr[N]!=wgaddr[N-1]) & (rgaddr[N-1]==wgaddr[N]);
    wire dirset = (rgaddr[N]==wgaddr[N-1]) & (rgaddr[N-1]!=wgaddr[N]);
    always @(posedge dirclr, posedge dirset)
        if (dirclr) dir <= 0;
        else dir <= 1;
endmodule
