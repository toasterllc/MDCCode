`timescale 1ns/1ps
`include "../SDRAMController.v"
`include "../ClockGen.v"
`include "../mt48h32m16lf/mt48h32m16lf.v"

module Top(
    input wire          ice_clk12mhz,   // 12 MHz crystal

    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire         ram_udqm,
    output wire         ram_ldqm,
    inout wire[15:0]    ram_dq
);
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
    ) cg(.clk12mhz(ice_clk12mhz), .clk(clk), .rst(rst));

    // RAM
    wire                    cmdReady;
    reg                     cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  cmdAddr = 0;
    reg                     cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  cmdWriteData = 0;

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

`ifdef SIM
    mt48h32m16lf sdram(
        .Dq(ram_dq),
        .Addr(ram_a),
        .Ba(ram_ba),
        .Clk(ram_clk),
        .Cke(ram_cke),
        .Cs_n(ram_cs_),
        .Ras_n(ram_ras_),
        .Cas_n(ram_cas_),
        .We_n(ram_we_),
        .Dqm({ram_udqm, ram_ldqm})
    );

    initial begin
       $dumpfile("top.vcd");
       $dumpvars(0, Top);
       #1000000;
       $finish;
      end
`endif

endmodule










// `timescale 1ns/1ps
// `include "../SDRAMController.v"
// `include "../ClockGen.v"
// `include "../mt48h32m16lf/mobile_sdr.v"
//
// module Top(
//     input wire          ice_clk12mhz,   // 12 MHz crystal
//
//     output wire         ram_clk,
//     output wire         ram_cke,
//     output wire[1:0]    ram_ba,
//     output wire[12:0]   ram_a,
//     output wire         ram_cs_,
//     output wire         ram_ras_,
//     output wire         ram_cas_,
//     output wire         ram_we_,
//     output wire         ram_udqm,
//     output wire         ram_ldqm,
//     inout wire[15:0]    ram_dq
// );
//     localparam ClockFrequency = 100000000; // 100 MHz
//
//     localparam RAM_AddrWidth = 25;
//     localparam RAM_DataWidth = 16;
//
//     // 100 MHz clock
//     wire clk;
//     wire rst;
//     ClockGen #(
//         .FREQ(ClockFrequency),
//         .DIVR(0),
//         .DIVF(66),
//         .DIVQ(3),
//         .FILTER_RANGE(1)
//     ) cg(.clk12mhz(ice_clk12mhz), .clk(clk), .rst(rst));
//
//     // RAM
//     wire                    cmdReady;
//     reg                     cmdTrigger = 0;
//     reg[RAM_AddrWidth-1:0]  cmdAddr = 0;
//     reg                     cmdWrite = 0;
//     reg[RAM_DataWidth-1:0]  cmdWriteData = 0;
//
//     SDRAMController #(
//         .ClockFrequency(ClockFrequency)
//     ) sdramController(
//         .clk(clk),
//         .rst(rst), // TODO: figure out resetting
//
//         .cmdReady(cmdReady),
//         .cmdTrigger(cmdTrigger),
//         .cmdAddr(cmdAddr),
//         .cmdWrite(cmdWrite),
//         .cmdWriteData(cmdWriteData),
//         .cmdReadData(),
//         .cmdReadDataValid(),
//
//         .sdram_clk(ram_clk),
//         .sdram_cke(ram_cke),
//         .sdram_ba(ram_ba),
//         .sdram_a(ram_a),
//         .sdram_cs_(ram_cs_),
//         .sdram_ras_(ram_ras_),
//         .sdram_cas_(ram_cas_),
//         .sdram_we_(ram_we_),
//         .sdram_udqm(ram_udqm),
//         .sdram_ldqm(ram_ldqm),
//         .sdram_dq(ram_dq)
//     );
//
//     always @(posedge clk) begin
//         if (!cmdTrigger) begin
//             cmdTrigger <= 1;
//             cmdWrite <= 1;
//             cmdAddr <= 0;
//             cmdWriteData <= 0;
//
//         end else if (cmdReady) begin
//             cmdAddr <= cmdAddr+1;
//             cmdWriteData <= cmdAddr+1;
//         end
//     end
//
// `ifdef SIM
//     mobile_sdr sdram(
//         .clk(ram_clk),
//         .dq(ram_dq),
//         .addr(ram_a),
//         .ba(ram_ba),
//         .cke(ram_cke),
//         .cs_n(ram_cs_),
//         .ras_n(ram_ras_),
//         .cas_n(ram_cas_),
//         .we_n(ram_we_),
//         .dqm({ram_udqm, ram_ldqm})
//     );
//
//     initial begin
//        $dumpfile("top.vcd");
//        $dumpvars(0, Top);
//        #210000000;
//        $finish;
//       end
// `endif
//
// endmodule
