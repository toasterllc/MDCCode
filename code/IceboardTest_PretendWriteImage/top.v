`timescale 1ns/1ps
`include "../SDRAMController.v"
`include "../AFIFO.v"
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
    input wire          clk12mhz,   // 12 MHz crystal
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[11:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire         ram_udqm,
    output wire         ram_ldqm,
    inout wire[15:0]    ram_dq,
    
    input wire          pix_clk,    // Clock from image sensor
    input wire          pix_frameValid,
    input wire          pix_lineValid,
    input wire[11:0]    pix_d       // Data from image sensor
);
    localparam ClockFrequency = 100000000; // 100 MHz
    
    localparam RAM_AddrWidth = 23;
    localparam RAM_DataWidth = 16;
    
    wire clk;
    ClockGenerator clockGen(
        .clock_in(clk12mhz),
        .clock_out(clk),
        .locked()
    );
    
    // RAM
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    wire[RAM_DataWidth-1:0] ram_cmdWriteData;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        .rst(0), // TODO: figure out resetting
        
        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(),
        .cmdReadDataValid(),
        
        .sdram_clk(ram_clk),
        .sdram_cke(ram_cke),
        .sdram_ba(ram_ba),
        .sdram_a(ram_a),
        .sdram_cs_(ram_cs_),
        .sdram_ras_(ram_ras_),
        .sdram_cas_(ram_cas_),
        .sdram_we_(ram_we_),
        .sdram_udqm(ram_udqm),
        .sdram_ldqm(ram_ldqm),
        .sdram_dq(ram_dq)
    );
    
    // Pixel buffer
    wire[11:0] pixbuf_data;
    wire pixbuf_read;
    wire pixbuf_canRead;
    wire pixbuf_canWrite;
    AFIFO #(.Width(12), .Size(32)) pixbuf(
        .rclk(clk),
        .r(pixbuf_read),
        .rd(pixbuf_data),
        .rok(pixbuf_canRead),

        .wclk(pix_clk),
        .w(pix_frameValid & pix_lineValid),
        .wd(pix_d),
        .wok(pixbuf_canWrite)
    );
    
    // // Handle pixbuf becoming full
    // always @(posedge clk) begin
    //     // TODO: handle pixbuf being full -- should never happen as long as we're consuming pixels at a rate >= the pixel production rate
    //     if (!pixbuf_canWrite);
    // end
    
    // // Logic
    // assign ram_cmdWriteData = {4'b0, pixbuf_data};
    //
    // wire writePixel = ram_cmdReady & ram_cmdTrigger & ram_cmdWrite & pixbuf_canRead;
    // assign pixbuf_read = writePixel;
    //
    // always @(posedge clk) begin
    //     if (!ram_cmdTrigger) begin
    //         ram_cmdTrigger <= 1;
    //         ram_cmdWrite <= 1;
    //
    //     end else if (writePixel) begin
    //         ram_cmdAddr <= ram_cmdAddr+1;
    //     end
    // end
    
    
    
    assign ram_cmdWriteData = 0;
    
    wire writePixel = ram_cmdReady & ram_cmdTrigger & ram_cmdWrite & pixbuf_canRead;
    assign pixbuf_read = writePixel;
    
    always @(posedge clk) begin
        if (!ram_cmdTrigger) begin
            ram_cmdTrigger <= 1;
            ram_cmdWrite <= 1;
        
        end else if (writePixel) begin
            ram_cmdAddr <= ram_cmdAddr+1;
        end
    end
    
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
