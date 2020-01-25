`timescale 1ns/1ps




module FIFO(
    input logic clk,
    
    input logic din,
    input logic[Width-1:0] d,
    
    input logic qout,
    output logic[Width-1:0] q,
    output logic qValid
);
    parameter Width = 12;
    parameter Slots = 3;
    
    logic[(Width*Slots)-1:0] slots;
    logic[Slots-1:0] qSlot;
    initial begin
        slots = 0;
        qSlot = 0;
    end
    
    logic empty;
    assign empty = qSlot==0;
    
    logic full;
    assign full = qSlot[Slots-1];
    
    always @(posedge clk) begin
        // Data in + data out
        if (din & qout) begin
            slots <= (slots<<Width) | d;
            qSlot <= (empty ? 1 : qSlot);
        
        // Data in
        end else if (din) begin
            slots <= (slots<<Width) | d;
            qSlot <= (empty ? 1 : (full ? qSlot : qSlot<<1));
        
        // Data out
        end else if (qout) begin
            qSlot <= qSlot>>1;
        end
    end
    
    integer i;
    always @* begin
        q = 0;
        for (i=0; i<Slots; i=i+1) begin
            if (qSlot[i]) begin
                q = q|slots[(Width*(i+1))-1 -: Width];
            end
        end
    end
    
    assign qValid = !empty;
endmodule









// module FIFO(
//     input logic clk,
//
//     input logic din,
//     input logic[Width-1:0] d,
//
//     input logic qout,
//     output logic[Width-1:0] q,
//     output logic qValid
// );
//     parameter Width = 12;
//     parameter Slots = 3;
//
//     logic[(Width*Slots)-1:0] slots;
//     logic[Slots-1:0] usedSlots;
//
//     always @(posedge clk) begin
//         // Data in + data out
//         if (din & qout) begin
//             slots <= (slots<<Width) | d;
//             // usedSlots doesn't change
//
//         // Data in
//         end else if (din) begin
//             slots <= (slots<<Width) | d;
//             usedSlots <= usedSlots<<1 | 1'b1;
//
//         // Data out
//         end else if (qout) begin
//             usedSlots <= usedSlots>>1;
//         end
//     end
//
//     assign q = slots[Width-1:0];
//     assign qValid = usedSlots[0];
// endmodule






// module FIFO(
//     input logic clk,
//
//     input logic din,
//     input logic[Width-1:0] d,
//
//     input logic qout,
//     output logic[Width-1:0] q,
//     output logic qValid
// );
//     parameter Width = 12;
//     parameter Slots = 3;
//
//     logic[(Width*Slots)-1:0] slots;
//     logic[Slots-1:0] usedSlots;
//
//     logic full;
//     assign full = usedSlots[Slots-1];
//
//     logic empty;
//     assign empty = !usedSlots[0];
//
//     // logic in;
//     // assign in = din & !usedSlots[Slots-1];
//     //
//     // logic out;
//     // assign out = qout & usedSlots[0];
//
//     logic[(Width*Slots)-1:0] slotsNext;
//     genvar i;
//     generate
//         for (i=0; i<Slots; i=i+1) begin
//             assign vacant = (i>0 ? !usedSlots[i] & usedSlots[i-1] : !usedSlots[0]);
//             assign lastUsed = (i>0 ? usedSlots[i] & usedSlots[i-1] : !usedSlots[0]);
//             assign slotsNext[(Width*(i+1))-1 -: Width] = (
//                 din & !qout & vacant ? d :
//                 din & qout & !empty & vacant :
//
//             );
//
//             // if (i > 0) begin
//             //     assign slotsNext[(Width*(i+1))-1 -: Width] = (
//             //         din & !qout & vacant ? d :
//             //         din & qout & !empty & vacant
//             //     );
//             //     // always_comb begin
//             //     //     slotsNext[(Width*(i+1))-1 -: Width] = 0;
//             //     // end
//             //     // assign slotsNext[(Width*(i+1))-1 -: Width] =
//             //     // if (din & !qout & vacant) begin
//             //     //     // slotsNext[(Width*(i+1))-1 -: Width] = d;
//             //     // end else if (din & qout & !empty & vacant) begin
//             //     //
//             //     // end else begin
//             //     //     // slotsNext[(Width*(i+1))-1 -: Width] = slots[(Width*(i+1))-1 -: Width];
//             //     // end
//             // end else begin
//             //     // always if (!usedSlots[0]) begin
//             //     //     slotsNext[Width-1 : 0] = d;
//             //     // end else begin
//             //     //     slotsNext[Width-1 : 0] = slots[Width-1 : 0];
//             //     // end
//             // end
//         end
//     endgenerate
//
//     always @(posedge clk) begin
//         // Data in + data out
//         if (din & qout) begin
//             slots <= slotsNext;
//             // usedSlots doesn't change
//
//         // Data in
//         end else if (din & !full) begin
//             slots <= slotsNext;
//             usedSlots <= usedSlots<<1 | 1'b1;
//
//         // Data out
//         end else if (qout) begin
//             slots <= slots>>Width;
//             usedSlots <= usedSlots>>1;
//         end
//     end
//
//     assign q = slots[Width-1:0];
//     assign qValid = usedSlots[0];
// endmodule





module FIFOTest(
    input logic         pix_clk,    // Clock from image sensor
    input logic         pix_frameValid,
    input logic         pix_lineValid,
    input logic[11:0]   pix_d,      // Data from image sensor
    
    output logic[11:0]  q,
    output logic        qValid
);
    logic din;
    logic[11:0] d;
    logic qout;
    
    FIFO #(.Width(12), .Slots(3)) fifo(
        .clk(pix_clk),
        
        .din(din),
        .d(d),
        .qout(qout),
        .q(q),
        .qValid(qValid)
    );
    
    
    // // One-hot implementation
    // localparam PixBufferSize = 3;
    // logic[(12*PixBufferSize)-1:0] pixBuffer;
    // logic[PixBufferSize-1:0] pixBufferValidData;
    //
    // logic full;
    // assign full = pixBufferValidData[PixBufferSize-1];
    //
    // logic[(12*PixBufferSize)-1:0] pixBufferNext;
    // genvar i;
    // for (i=0; i<PixBufferSize; i=i+1) begin
    //     // assign pixBufferNext[(12*(i+1))-1 -: 12] = pix_d & (i>0 ? !pixBufferValidData[i] && pixBufferValidData[i-1] : !pixBufferValidData[i]);
    //
    //     if (i > 0)
    //         assign pixBufferNext[(12*(i+1))-1 -: 12] = pix_d & {12{(!pixBufferValidData[i] & pixBufferValidData[i-1])}};
    //     else
    //         assign pixBufferNext[(12*(i+1))-1 -: 12] = pix_d & {12{!pixBufferValidData[i]}};
    //     // pixBufferNext <= ;
    //     // `ifdef SIM
    //     //     // For simulation, use a normal tristate buffer
    //     //     assign sdram_dq[i] = (writeDataValid ? sdram_writeData[i] : 1'bz);
    //     //     assign cmdReadData[i] = sdram_dq[i];
    //     // `else
    //     //     // For synthesis, we have to use a SB_IO for a tristate buffer
    //     //     SB_IO #(
    //     //         .PIN_TYPE(6'b1010_01),
    //     //         .PULLUP(0),
    //     //     ) dqio (
    //     //         .PACKAGE_PIN(sdram_dq[i]),
    //     //         .OUTPUT_ENABLE(writeDataValid),
    //     //         .D_OUT_0(sdram_writeData[i]),
    //     //         .D_IN_0(cmdReadData[i]),
    //     //     );
    //     // `endif
    // end
    //
    // always @(posedge pix_clk) begin
    //     // Data in
    //     if (pix_frameValid && pix_lineValid) begin
    //
    //         // If we're not full
    //         if (!full) begin
    //             pixBufferValidData <= pixBufferValidData<<1 | 1'b1;
    //             pixBuffer <= pixBufferNext;
    //
    //             // if ()
    //
    //         end
    //
    //         // for (int i=0; i<X; i++) begin
    //         //     // if (onehot == (1 << i)) begin
    //         //     //     o_data = i_data[i];
    //         //     // end
    //         // end
    //
    //         // if (!pixBufferValidData[0]) begin
    //         //     pixBuffer[11:0] <= pix_d;
    //         //     pixBufferValidData[0] <= 1;
    //         //
    //         // end else if (!pixBufferValidData[1]) begin
    //         //     pixBuffer[23:12] <= pix_d;
    //         //     pixBufferValidData[1] <= 1;
    //         //
    //         // end else if (!pixBufferValidData[2]) begin
    //         //     pixBuffer[35:24] <= pix_d;
    //         //     pixBufferValidData[2] <= 1;
    //         // end
    //
    //     // Data out
    //     end else begin
    //         pixBuffer <= pixBuffer>>12;
    //         pixBufferValidData <= pixBufferValidData>>1;
    //     end
    // end
    //
    // assign q = pixBuffer[11:0];
    // assign qValid = pixBufferValidData[0];
    //
    // // // Integer implementation
    // // localparam PixBufferSize = 3;
    // // logic[(12*PixBufferSize)-1:0] pixBuffer;
    // // logic[$clog2(PixBufferSize)-1:0] pixBufferCount;
    // //
    // // always @(posedge pix_clk) begin
    // //     // Produce data
    // //     if (pix_frameValid && pix_lineValid) begin
    // //         if (pixBufferCount < PixBufferSize) begin
    // //             pixBuffer <= pixBuffer|(pix_d<<(pixBufferCount*12));
    // //             pixBufferCount <= pixBufferCount+1;
    // //         end
    // //
    // //     // Consume data
    // //     end else begin
    // //         pixBuffer <= pixBuffer>>12;
    // //         pixBufferCount <= (pixBufferCount>0 ? pixBufferCount-1 : 0);
    // //     end
    // // end
    // //
    // // assign q = pixBuffer[11:0];
    // // assign qValid = pixBufferCount>0;
endmodule

`ifdef SIM

module FIFOTestSim(
);
    logic clk;
    logic din;
    logic[7:0] d;
    logic qout;
    logic[7:0] q;
    logic qValid;
    
    FIFO #(.Width(8), .Slots(3)) fifo(
        .clk(clk),
        .din(din),
        .d(d),
        .qout(qout),
        .q(q),
        .qValid(qValid)
    );
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, FIFOTestSim);
       
       
       clk = 0;
       
       din = 1;
       d = 8'hA;
       #1; clk = 1;
       #1; clk = 0;
       din = 0;
       
       din = 1;
       d = 8'hB;
       #1; clk = 1;
       #1; clk = 0;
       din = 0;
       
       din = 1;
       d = 8'hC;
       #1; clk = 1;
       #1; clk = 0;
       din = 0;
       
       // din = 1;
       // d = 8'hD;
       // #1; clk = 1;
       // #1; clk = 0;
       // din = 0;
       
       $display("q: %h (valid: %d)", q, qValid);
       qout = 1;
       #1; clk = 1;
       #1; clk = 0;
       qout = 0;
       
       $display("q: %h (valid: %d)", q, qValid);
       qout = 1;
       #1; clk = 1;
       #1; clk = 0;
       qout = 0;
       
       $display("q: %h (valid: %d)", q, qValid);
       qout = 1;
       #1; clk = 1;
       #1; clk = 0;
       qout = 0;
       
       $display("q: %h (valid: %d)", q, qValid);
       qout = 1;
       #1; clk = 1;
       #1; clk = 0;
       qout = 0;
       
       $display("q: %h (valid: %d)", q, qValid);
       qout = 1;
       #1; clk = 1;
       #1; clk = 0;
       qout = 0;
       
       
       
       #10000000;
//        #200000000;
//        #2300000000;
       $finish;
    end
endmodule

`endif
