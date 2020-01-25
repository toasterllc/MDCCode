`timescale 1ns/1ps

module FIFOTest(
    input logic         pix_clk,    // Clock from image sensor
    input logic         pix_frameValid,
    input logic         pix_lineValid,
    input logic[11:0]   pix_d,      // Data from image sensor
    
    output logic[11:0]  q,
    output logic        qValid,
);
    // One-hot implementation
    localparam PixBufferSize = 3;
    logic[(12*PixBufferSize)-1:0] pixBuffer;
    logic[PixBufferSize-1:0] pixBufferValidData;
    
    logic full;
    assign full = pixBufferValidData[PixBufferSize-1];
    
    logic[(12*PixBufferSize)-1:0] pixBufferNext;
    genvar i;
    for (i=0; i<PixBufferSize; i=i+1) begin
        // assign pixBufferNext[(12*(i+1))-1 -: 12] = pix_d & (i>0 ? !pixBufferValidData[i] && pixBufferValidData[i-1] : !pixBufferValidData[i]);
        
        if (i > 0)
            assign pixBufferNext[(12*(i+1))-1 -: 12] = pix_d & {12{(!pixBufferValidData[i] & pixBufferValidData[i-1])}};
        else
            assign pixBufferNext[(12*(i+1))-1 -: 12] = pix_d & {12{!pixBufferValidData[i]}};
        // pixBufferNext <= ;
        // `ifdef SIM
        //     // For simulation, use a normal tristate buffer
        //     assign sdram_dq[i] = (writeDataValid ? sdram_writeData[i] : 1'bz);
        //     assign cmdReadData[i] = sdram_dq[i];
        // `else
        //     // For synthesis, we have to use a SB_IO for a tristate buffer
        //     SB_IO #(
        //         .PIN_TYPE(6'b1010_01),
        //         .PULLUP(0),
        //     ) dqio (
        //         .PACKAGE_PIN(sdram_dq[i]),
        //         .OUTPUT_ENABLE(writeDataValid),
        //         .D_OUT_0(sdram_writeData[i]),
        //         .D_IN_0(cmdReadData[i]),
        //     );
        // `endif
    end
    
    always @(posedge pix_clk) begin
        // Data in
        if (pix_frameValid && pix_lineValid) begin
            
            // If we're not full
            if (!full) begin
                pixBufferValidData <= pixBufferValidData<<1 | 1'b1;
                pixBuffer <= pixBufferNext;
                
                // if ()
                
            end
            
            // for (int i=0; i<X; i++) begin
            //     // if (onehot == (1 << i)) begin
            //     //     o_data = i_data[i];
            //     // end
            // end
            
            // if (!pixBufferValidData[0]) begin
            //     pixBuffer[11:0] <= pix_d;
            //     pixBufferValidData[0] <= 1;
            //
            // end else if (!pixBufferValidData[1]) begin
            //     pixBuffer[23:12] <= pix_d;
            //     pixBufferValidData[1] <= 1;
            //
            // end else if (!pixBufferValidData[2]) begin
            //     pixBuffer[35:24] <= pix_d;
            //     pixBufferValidData[2] <= 1;
            // end
        
        // Data out
        end else begin
            pixBuffer <= pixBuffer>>12;
            pixBufferValidData <= pixBufferValidData>>1;
        end
    end
    
    assign q = pixBuffer[11:0];
    assign qValid = pixBufferValidData[0];
    
    // // Integer implementation
    // localparam PixBufferSize = 3;
    // logic[(12*PixBufferSize)-1:0] pixBuffer;
    // logic[$clog2(PixBufferSize)-1:0] pixBufferCount;
    //
    // always @(posedge pix_clk) begin
    //     // Produce data
    //     if (pix_frameValid && pix_lineValid) begin
    //         if (pixBufferCount < PixBufferSize) begin
    //             pixBuffer <= pixBuffer|(pix_d<<(pixBufferCount*12));
    //             pixBufferCount <= pixBufferCount+1;
    //         end
    //
    //     // Consume data
    //     end else begin
    //         pixBuffer <= pixBuffer>>12;
    //         pixBufferCount <= (pixBufferCount>0 ? pixBufferCount-1 : 0);
    //     end
    // end
    //
    // assign q = pixBuffer[11:0];
    // assign qValid = pixBufferCount>0;
endmodule

`ifdef SIM

module FIFOTestSim(
);

    logic pix_clk;
    
    FIFOTest fifoTest(
        .pix_clk(pix_clk),
    );
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, FIFOTestSim);

       #10000000;
//        #200000000;
//        #2300000000;
//        $finish;
    end

    initial begin
        pix_clk = 0;
        forever begin
            pix_clk = !pix_clk;
            #42;
        end
    end
endmodule

`endif
