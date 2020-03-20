`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../SDRAMController.v"
`include "../AFIFO.v"

`ifdef SIM
`include "../Icestick_AFIFOProducer/Icestick_AFIFOProducer.v"
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

module Top(
    input wire          clk12mhz,   // 12 MHz crystal
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq,
    
    input wire          pix_clk,    // Clock from image sensor
    input wire          pix_fv,
    input wire          pix_lv,
    input wire[11:0]    pix_d       // Data from image sensor
);
    localparam ClockFrequency = 100000000; // 100 MHz
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;
    
    // 100 MHz clock
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
		.DIVR(0),
		.DIVF(66),
		.DIVQ(3),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
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
        
        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(),
        .cmdReadDataValid(),
        
        .ram_clk(ram_clk),
        .ram_cke(ram_cke),
        .ram_ba(ram_ba),
        .ram_a(ram_a),
        .ram_cs_(ram_cs_),
        .ram_ras_(ram_ras_),
        .ram_cas_(ram_cas_),
        .ram_we_(ram_we_),
        .ram_dqm(ram_dqm),
        .ram_dq(ram_dq)
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
        .w(pix_fv & pix_lv),
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
            $display("Copied value: %h", pixbuf_data);
            ram_cmdTrigger <= 1;
            ram_cmdWrite <= 1;
            ram_cmdWriteData <= {4'b0, pixbuf_data};
        end
    end
    
`ifdef SIM
    // Produce data
    wire w;
    assign pix_fv = w;
    assign pix_lv = w;
    Icestick_AFIFOProducer producer(.clk(clk), .wclk(pix_clk), .w(w), .wd(pix_d));
    
    mobile_sdr sdram (
        .clk(ram_clk),
        .cke(ram_cke),
        .addr(ram_a),
        .ba(ram_ba),
        .cs_n(ram_cs_),
        .ras_n(ram_ras_),
        .cas_n(ram_cas_),
        .we_n(ram_we_),
        .dq(ram_dq),
        .dqm(ram_dqm)
    );
    
    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, Top);
       #1000000000;
       $finish;
    end
`endif
endmodule
