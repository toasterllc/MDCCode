module afifo2 (rdata, wfull, rempty, wdata, winc, wclk, rinc, rclk);
    parameter DSIZE = 8;
    parameter ASIZE = 4;
    output [DSIZE-1:0] rdata;
    output wfull;
    output rempty;
    input [DSIZE-1:0] wdata;
    input winc, wclk;
    input rinc, rclk;
    wire [ASIZE-1:0] wptr, rptr;
    wire [ASIZE-1:0] waddr, raddr;
    wire aempty_n;
    wire afull_n;
    
    async_cmp #(ASIZE) async_cmp(.aempty_n(aempty_n), .afull_n(afull_n), .wptr(wptr), .rptr(rptr));
    fifomem #(DSIZE, ASIZE) fifomem(.rdata(rdata), .wdata(wdata), .waddr(wptr), .raddr(rptr), .wclken(winc), .wclk(wclk));
    rptr_empty #(ASIZE) rptr_empty(.rempty(rempty), .rptr(rptr), .aempty_n(aempty_n), .rinc(rinc), .rclk(rclk));
    wptr_full #(ASIZE) wptr_full(.wfull(wfull), .wptr(wptr), .afull_n(afull_n), .winc(winc), .wclk(wclk));
endmodule


module fifomem (rdata, wdata, waddr, raddr, wclken, wclk);
    parameter DATASIZE = 8; // Memory data word width
    parameter ADDRSIZE = 4; // Number of memory address bits
    parameter DEPTH = 1<<ADDRSIZE; // DEPTH = 2**ADDRSIZE
    output [DATASIZE-1:0] rdata;
    input [DATASIZE-1:0] wdata;
    input [ADDRSIZE-1:0] waddr, raddr;
    input wclken, wclk;
    
    reg [DATASIZE-1:0] MEM [0:DEPTH-1];
    assign rdata = MEM[raddr];
    always @(posedge wclk)
        if (wclken) MEM[waddr] <= wdata;
endmodule








module async_cmp(aempty_n, afull_n, wptr, rptr);
    parameter ADDRSIZE = 4;
    parameter N = ADDRSIZE-1;
    output aempty_n, afull_n;
    input [N:0] wptr, rptr;
    reg dir = 0;
    wire dirset = (wptr[N]^rptr[N-1]) & ~(wptr[N-1]^rptr[N]);
    wire dirclr = (~(wptr[N]^rptr[N-1]) & (wptr[N-1]^rptr[N]));
    // always @(posedge high or negedge dirset_n or negedge dirclr_n)
    //     if (!dirclr_n) dir <= 1'b0;
    //     else if (!dirset_n) dir <= 1'b1;
    //     else dir <= high;
    always @(posedge dirclr, posedge dirset)
        if (dirclr) dir <= 1'b0;
        else dir <= 1'b1;
    assign aempty_n = ~((wptr == rptr) && !dir);
    assign afull_n = ~((wptr == rptr) && dir);
endmodule



// module async_cmp (aempty_n, afull_n, wptr, rptr, wrst_n);
//     parameter ADDRSIZE = 4;
//     parameter N = ADDRSIZE-1;
//     output aempty_n, afull_n;
//     input [N:0] wptr, rptr;
//     input wrst_n;
//     reg dir;
//
//     wire high = 1'b1;
//     wire dirset_n = ~( (wptr[N]^rptr[N-1]) & ~(wptr[N-1]^rptr[N]));
//     wire dirclr_n = ~((~(wptr[N]^rptr[N-1]) & (wptr[N-1]^rptr[N])) | ~wrst_n);
//     // always @(posedge high or negedge dirset_n or negedge dirclr_n)
//     //     if (!dirclr_n) dir <= 1'b0;
//     //     else if (!dirset_n) dir <= 1'b1;
//     //     else dir <= high;
//     always @(negedge dirset_n or negedge dirclr_n)
//         if (!dirclr_n) dir <= 1'b0;
//         else dir <= 1'b1;
//     assign aempty_n = ~((wptr == rptr) && !dir);
//     assign afull_n = ~((wptr == rptr) && dir);
// endmodule



// module async_cmp (aempty_n, afull_n, wptr, rptr);
//     parameter ADDRSIZE = 4;
//     parameter N = ADDRSIZE-1;
//     output aempty_n, afull_n;
//     input [N:0] wptr, rptr;
//     reg dir;
//
//     wire dirset = (wptr[N]^rptr[N-1]) & ~(wptr[N-1]^rptr[N]);
//     wire dirclr = (~(wptr[N]^rptr[N-1]) & (wptr[N-1]^rptr[N]));
//     always @(posedge dirclr or posedge dirset)
//         if (dirclr) dir <= 1'b0;
//         else dir <= 1'b1;
//
//     //always @(negedge dirset_n or negedge dirclr_n)
//     //if (!dirclr_n) dir <= 1'b0;
//     //else dir <= 1'b1;
//     assign aempty_n = ~((wptr == rptr) && !dir);
//     assign afull_n = ~((wptr == rptr) && dir);
// endmodule




module rptr_empty (rempty, rptr, aempty_n, rinc, rclk);
    parameter ADDRSIZE = 4;
    output rempty;
    output [ADDRSIZE-1:0] rptr;
    input aempty_n;
    input rinc, rclk;
    reg [ADDRSIZE-1:0] rptr, rbin=0;
    reg rempty=0, rempty2=0;
    wire [ADDRSIZE-1:0] rgnext, rbnext;
    //---------------------------------------------------------------
    // GRAYSTYLE2 pointer
    //---------------------------------------------------------------
    always @(posedge rclk) begin
        rbin <= rbnext;
        rptr <= rgnext;
    end
    //---------------------------------------------------------------
    // increment the binary count if not empty
    //---------------------------------------------------------------
    assign rbnext = !rempty ? rbin + rinc : rbin;
    assign rgnext = (rbnext>>1) ^ rbnext; // binary-to-gray conversion
    always @(posedge rclk or negedge aempty_n)
        if (!aempty_n) {rempty,rempty2} <= 2'b11;
        else {rempty,rempty2} <= {rempty2,~aempty_n};
endmodule



module wptr_full (wfull, wptr, afull_n, winc, wclk);
    parameter ADDRSIZE = 4;
    output wfull;
    output [ADDRSIZE-1:0] wptr;
    input afull_n;
    input winc, wclk;
    reg [ADDRSIZE-1:0] wptr=0, wbin=0;
    reg wfull=0, wfull2=0;
    wire [ADDRSIZE-1:0] wgnext, wbnext;
    
    //---------------------------------------------------------------
    // GRAYSTYLE2 pointer
    //---------------------------------------------------------------
    always @(posedge wclk) begin
        wbin <= wbnext;
        wptr <= wgnext;
    end
    
    //---------------------------------------------------------------
    // increment the binary count if not full
    //---------------------------------------------------------------
    assign wbnext = !wfull ? wbin + winc : wbin;
    assign wgnext = (wbnext>>1) ^ wbnext; // binary-to-gray conversion
    always @(posedge wclk or negedge afull_n)
        if (!afull_n) {wfull,wfull2} <= 2'b11;
        else {wfull,wfull2} <= {wfull2,~afull_n};
endmodule