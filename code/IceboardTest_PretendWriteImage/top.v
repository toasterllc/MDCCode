`timescale 1ns/1ps
`include "../SDRAMController.v"
`include "../FIFO.v"
`include "../uart.v"

module ClockGenerator(
    input  clock_in,
    output clock_out,
    output locked
);
    SB_PLL40_CORE #(
    		.FEEDBACK_PATH("SIMPLE"),
    		.DIVR(4'b0000),		// DIVR =  0
    		.DIVF(7'b1000010),	// DIVF = 66
    		.DIVQ(3'b011),		// DIVQ =  3
    		.FILTER_RANGE(3'b001)	// FILTER_RANGE = 1
    	) uut (
    		.LOCK(locked),
    		.RESETB(1'b1),
    		.BYPASS(1'b0),
    		.REFERENCECLK(clock_in),
    		.PLLOUTCORE(clock_out)
    		);
endmodule

module IceboardTest_PretendWriteImage(
    input logic         clk12mhz,   // 12 MHz crystal
    
    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_udqm,
    output logic        sdram_ldqm,
    inout logic[15:0]   sdram_dq,
    
    input logic         pix_clk,    // Clock from image sensor
    input logic         pix_frameValid,
    input logic         pix_lineValid,
    input logic[11:0]   pix_d       // Data from image sensor
);
    // Generate our own reset signal
    // This relies on the fact that the ice40 FPGA resets flipflops to 0 at power up
    logic[12:0] rstCounter;
    logic rst;
    `ifdef SIM
    initial rstCounter = 0;
    `endif
    assign rst = !rstCounter[$size(rstCounter)-1];
    always @(posedge clk12mhz) begin
        if (rst) begin
            rstCounter <= rstCounter+1;
        end
    end
    
    localparam ClockFrequency = 100000000; // 100 MHz
    localparam AddrWidth = 23;
    localparam AddrCount = 'h800000;
    localparam AddrCountLimit = AddrCount;
    // localparam AddrCountLimit = AddrCount/1024; // 32k words
    // localparam AddrCountLimit = AddrCount/8192; // 1k words
    localparam DataWidth = 16;
    localparam MaxEnqueuedReads = 10;
    
    logic clk;
    ClockGenerator clockGen(
        .clock_in(clk12mhz),
        .clock_out(clk),
        .locked()
    );
    
    logic                   cmdReady;
    logic                   cmdTrigger;
    logic[AddrWidth-1:0]    cmdAddr;
    logic                   cmdWrite;
    logic[DataWidth-1:0]    cmdWriteData;
    logic[DataWidth-1:0]    cmdReadData;
    logic                   cmdReadDataValid;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        .rst(rst),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_udqm(sdram_udqm),
        .sdram_ldqm(sdram_ldqm),
        .sdram_dq(sdram_dq)
    );
    
    AFIFO #(.Size(32)) pixBuffer(
        .rclk(clk),
        .r(pix_frameValid & pix_lineValid),
        .rd(pix_d),
        .rempty(rempty),
        
        .wclk(wclk),
        .w(w),
        .wd(wd),
        .wfull()
    );
    
    always @(posedge clk) begin
        if (rst) begin
            cmdTrigger <= 0;
        
        // Initialize memory to known values
        end else begin
            // Start
            if (!cmdTrigger) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 0;
                cmdWriteData <= 0;
            
            // Continue
            end else if (cmdReady) begin
                cmdAddr <= cmdAddr+1;
                cmdWriteData <= cmdAddr;
            end
        end
    end
    
    localparam PixelWidth = 12; // Width of a single pixel
    localparam PixelBufferSlots = 10; // Number of pixels that the buffer contains
    FIFO #(
        .Width(PixelWidth),
        .Slots(PixelBufferSlots)
    ) pixBuffer(
        .clk(pix_clk),
        
        .din(pix_frameValid & pix_lineValid),
        .d(pix_d),
        
        .qout(),
        .q(),
        .qValid()
    );
endmodule

`ifdef SIM

`include "../4062mt48lc8m16a2/mt48lc8m16a2.v"
`include "../4012mt48lc16m16a2/mt48lc16m16a2.v"

module IceboardTest_PretendWriteImageSim(
    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_udqm,
    output logic        sdram_ldqm,
    inout logic[15:0]   sdram_dq
);

    logic clk12mhz;
    
    IceboardTest_PretendWriteImage iceboardSDRAMTest(
        .clk12mhz(clk12mhz),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_udqm(sdram_udqm),
        .sdram_ldqm(sdram_ldqm),
        .sdram_dq(sdram_dq)
    );
    
    mt48lc8m16a2 sdram(
        .Clk(sdram_clk),
        .Dq(sdram_dq),
        .Addr(sdram_a),
        .Ba(sdram_ba),
        .Cke(sdram_cke),
        .Cs_n(sdram_cs_),
        .Ras_n(sdram_ras_),
        .Cas_n(sdram_cas_),
        .We_n(sdram_we_),
        .Dqm({sdram_udqm, sdram_ldqm})
    );
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, IceboardTest_PretendWriteImageSim);

       #10000000;
//        #200000000;
//        #2300000000;
//        $finish;
    end

    initial begin
        clk12mhz = 0;
        forever begin
            clk12mhz = !clk12mhz;
            #42;
        end
    end
endmodule

`endif
