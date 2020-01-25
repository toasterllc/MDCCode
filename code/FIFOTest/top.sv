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
    logic[PixBufferSize-1:0] pixBufferValidData; // One-hot
    
    always @(posedge pix_clk) begin
        // Data in
        if (pix_frameValid && pix_lineValid) begin
            if (!pixBufferValidData[0]) begin
                pixBuffer[11:0] <= pix_d;
                pixBufferValidData[0] <= 1;
            
            end else if (!pixBufferValidData[1]) begin
                pixBuffer[23:12] <= pix_d;
                pixBufferValidData[1] <= 1;
            
            end else if (!pixBufferValidData[2]) begin
                pixBuffer[35:24] <= pix_d;
                pixBufferValidData[2] <= 1;
            end
        
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
