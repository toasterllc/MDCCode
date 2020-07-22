// Based on Clifford E. Cummings paper:
//   http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf
module AFIFO #(
    parameter Width=12,
    parameter Size=4 // Must be a power of 2 and >=4
)(
    input wire rclk,                // Read clock
    input wire rtrigger,            // Read trigger
    output wire[Width-1:0] rdata,   // Read data
    output wire rok,                // Read OK (data available -- not empty)
    
    input wire wclk,                // Write clock
    input wire wtrigger,            // Write trigger
    input wire[Width-1:0] wdata,    // Write data
    output wire wok                 // Write OK (space available -- not full)
);
    localparam N = $clog2(Size)-1;
    reg[Width-1:0] mem[Size-1:0];
    
    // ====================
    // Read handling
    // ====================
    // Don't init rbaddr=0, since that breaks RAM inference with Icestorm,
    // since it thinks rbaddr is async instead of being clocked by rclk
    reg[N:0] rbaddr, rgaddr=0; // Read addresses (binary, gray)
    
`ifdef SIM
    initial rbaddr = 0; // For simulation (see rbaddr comment above)
`endif
    
    wire[N:0] rbaddrNext = rbaddr+1'b1;
    always @(posedge rclk)
        if (rtrigger & rok) begin
            rbaddr <= rbaddrNext;
            rgaddr <= (rbaddrNext>>1)^rbaddrNext;
        end
    
    reg[1:0] rokReg = 0;
    always @(posedge rclk, negedge arok)
        if (!arok) rokReg <= 2'b00;
        else rokReg <= (rokReg<<1)|1'b1;
    
    assign rdata = mem[rbaddr];
    assign rok = rokReg[1];
    
    // ====================
    // Write handling
    // ====================
    reg[N:0] wbaddr=0, wgaddr=0, wgaddrDelayed=0; // Write address (binary, gray, gray delayed)
    wire[N:0] wbaddrNext = wbaddr+1'b1;
    always @(posedge wclk) begin
        wgaddrDelayed <= wgaddr;
        if (wtrigger & wok) begin
            mem[wbaddr] <= wdata;
            wbaddr <= wbaddrNext;
            wgaddr <= (wbaddrNext>>1)^wbaddrNext;
        end
    end
    
    reg[1:0] wokReg_ = 0; // Inverted logic so we come out of reset with wok==true
    always @(posedge wclk, negedge awok)
        if (!awok) wokReg_ <= 2'b11;
        else wokReg_ <= (wokReg_<<1)|1'b0;
    
    assign wok = !wokReg_[1];
    
    // ====================
    // Async signal generation
    // ====================
    reg dir = 0;
    wire arok = (rgaddr!=wgaddrDelayed) || dir; // Read OK == not empty
    wire awok = (rgaddr!=wgaddr) || !dir; // Write OK == not full
    wire dirclr = (rgaddr[N]!=wgaddr[N-1]) & (rgaddr[N-1]==wgaddr[N]);
    wire dirset = (rgaddr[N]==wgaddr[N-1]) & (rgaddr[N-1]!=wgaddr[N]);
    always @(posedge dirclr, posedge dirset)
        if (dirclr) dir <= 0;
        else dir <= 1;
endmodule
