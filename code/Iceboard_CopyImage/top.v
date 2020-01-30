`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../SDRAMController.v"
`include "../AFIFO.v"

// `include "../Icestick_AFIFOProducer/top.v"
// `include "../4062mt48lc8m16a2/mt48lc8m16a2.v"

module Iceboard_CopyImage(
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
    
    // 100 MHz clock
    wire clk;
    wire rst;
    ClockGen #(
        .FREQ(100),
		.DIVR(0),
		.DIVF(66),
		.DIVQ(3),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk), .rst(rst));
    
    // RAM controller
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        .rst(rst), // TODO: figure out resetting
        
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
    
    // Pixel FIFO buffer: asynchronous buffer with separate
    // producer (pix_clk) and consumer (clk) clocks
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
    
    // AFIFO -> RAM copy logic
    // Copy a pixel into RAM when:
    //   (1) data is available from pixbuf FIFO, AND
    //     (2a) there's no underway RAM write command, OR
    //     (2b) the underway RAM write command was accepted on this clock cycle
    wire copyPixel = pixbuf_canRead & (!ram_cmdTrigger | ram_cmdReady);
    assign pixbuf_read = copyPixel;
    always @(posedge clk) begin
        // Update our RAM state when a command is accepted
        if (ram_cmdTrigger & ram_cmdReady) begin
            ram_cmdTrigger <= 0;
            // Increment the address after the write completes (ie, not when issuing the write),
            // so that the first address is 0
            ram_cmdAddr <= ram_cmdAddr+1'b1;
        end
        
        if (copyPixel) begin
            $display("Copied pixel value into RAM: %h", pixbuf_data);
            ram_cmdTrigger <= 1;
            ram_cmdWrite <= 1;
            ram_cmdWriteData <= {4'b0, pixbuf_data};
        end
    end
    
`ifdef SIM
    // Produce data
    wire w;
    assign pix_frameValid = w;
    assign pix_lineValid = w;
    Icestick_AFIFOProducer producer(.clk12mhz(clk12mhz), .wclk(pix_clk), .w(w), .wd(pix_d));
    
    mt48lc8m16a2 sdram(
        .Clk(ram_clk),
        .Dq(ram_dq),
        .Addr(ram_a),
        .Ba(ram_ba),
        .Cke(ram_cke),
        .Cs_n(ram_cs_),
        .Ras_n(ram_ras_),
        .Cas_n(ram_cas_),
        .We_n(ram_we_),
        .Dqm({ram_udqm, ram_ldqm})
    );
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, Iceboard_CopyImage);
       #10000000000000;
       $finish;
      end
`endif
    
    
endmodule

// `ifdef SIM
//
// `include "../4062mt48lc8m16a2/mt48lc8m16a2.v"
// `include "../4012mt48lc16m16a2/mt48lc16m16a2.v"
//
// module Iceboard_CopyImageSim(
//     output logic        sdram_clk,
//     output logic        sdram_cke,
//     output logic[1:0]   sdram_ba,
//     output logic[11:0]  sdram_a,
//     output logic        sdram_cs_,
//     output logic        sdram_ras_,
//     output logic        sdram_cas_,
//     output logic        sdram_we_,
//     output logic        sdram_udqm,
//     output logic        sdram_ldqm,
//     inout logic[15:0]   sdram_dq
// );
//
//     logic clk12mhz;
//
//     Iceboard_CopyImage iceboardSDRAMTest(
//         .clk12mhz(clk12mhz),
//         .sdram_clk(sdram_clk),
//         .sdram_cke(sdram_cke),
//         .sdram_ba(sdram_ba),
//         .sdram_a(sdram_a),
//         .sdram_cs_(sdram_cs_),
//         .sdram_ras_(sdram_ras_),
//         .sdram_cas_(sdram_cas_),
//         .sdram_we_(sdram_we_),
//         .sdram_udqm(sdram_udqm),
//         .sdram_ldqm(sdram_ldqm),
//         .sdram_dq(sdram_dq)
//     );
//
//     mt48lc8m16a2 sdram(
//         .Clk(sdram_clk),
//         .Dq(sdram_dq),
//         .Addr(sdram_a),
//         .Ba(sdram_ba),
//         .Cke(sdram_cke),
//         .Cs_n(sdram_cs_),
//         .Ras_n(sdram_ras_),
//         .Cas_n(sdram_cas_),
//         .We_n(sdram_we_),
//         .Dqm({sdram_udqm, sdram_ldqm})
//     );
//
//     initial begin
//        $dumpfile("top.vcd");
//        $dumpvars(0, Iceboard_CopyImageSim);
//
//        #10000000;
// //        #200000000;
// //        #2300000000;
// //        $finish;
//     end
//
//     initial begin
//         clk12mhz = 0;
//         forever begin
//             clk12mhz = !clk12mhz;
//             #42;
//         end
//     end
// endmodule
//
// `endif
