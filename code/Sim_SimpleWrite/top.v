`timescale 1ns/1ps
`include "../SDRAMController.v"
`include "../ClockGen.v"
`include "../mt48h32m16lf/mobile_sdr.v"

module Top();
    localparam ClockFrequency = 100000000; // 100 MHz
    
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;

    // 100 MHz clock
    wire clk;
    wire rst;
    ClockGen #(
        .FREQ(ClockFrequency),
        .DIVR(0),
        .DIVF(66),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(), .clk(clk), .rst(rst));

    // RAM
    wire                    cmdReady;
    reg                     cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  cmdAddr = 0;
    reg                     cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  cmdWriteData = 0;
    
    wire         ram_clk;
    wire         ram_cke;
    wire[1:0]    ram_ba;
    wire[12:0]   ram_a;
    wire         ram_cs_;
    wire         ram_ras_;
    wire         ram_cas_;
    wire         ram_we_;
    wire[1:0]    ram_dqm;
    wire[15:0]   ram_dq;
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        .rst(rst), // TODO: figure out resetting

        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
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
    
    always @(posedge clk) begin
        if (!cmdTrigger) begin
            cmdTrigger <= 1;
            cmdWrite <= 1;
            cmdAddr <= 0;
            cmdWriteData <= 0;

        end else if (cmdReady) begin
            $display("Wrote %0d", cmdAddr);
            cmdAddr <= cmdAddr+1;
            cmdWriteData <= cmdWriteData+1;
        end
    end

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
       // #200905000;
       #10000000000;
       $finish;
      end
endmodule
