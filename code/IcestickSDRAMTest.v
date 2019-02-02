`define SYNTH
`timescale 1ns/1ps
`include "uart.v"
`include "SDRAMController.v"

module IcestickSDRAMTest(
    input logic         clk12mhz,

    output logic        ledRed,
    output logic        ledGreen,

    output logic        sdram_clk,
    output logic        sdram_cke,
    // Use the high bits of `sdram_a` because we need A[10] for precharging to work!
    output logic[11:4]  sdram_a,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_dqm,
    inout logic[7:0]    sdram_dq,

    input logic         RS232_Rx_TTL,
    output logic        RS232_Tx_TTL
);

    logic[23:0] clkDivider;

    `ifndef SYNTH
    initial clkDivider = 0;
    `endif

    always @(posedge clk12mhz)
        clkDivider <= clkDivider+1;

    logic doRead;
    assign doRead = (clkDivider == 'b1<<($size(clkDivider)-1));

    logic clk;
    assign clk = clkDivider[0];
    // assign clk = clk12mhz;

    `ifndef SYNTH
    initial rstCounter = 0;
    `endif

    logic[12:0] rstCounter;
    logic rst;
    assign rst = !rstCounter[$size(rstCounter)-1];
    always @(posedge clk) if (rst) rstCounter <= rstCounter+1;


    // assign ledGreen = needInit;
    // always @(posedge clk) begin
    //     if (rst) begin
    //         ledGreen <= 0;
    //         ledRed <= 1;
    //     end
    // end

    logic               cmdReady;
    logic               cmdTrigger;
    logic[20:13]        cmdAddr;
    logic               cmdWrite;
    logic[7:0]          cmdWriteData;
    logic[7:0]          cmdReadData;
    logic               cmdReadDataValid;

    logic[1:0]          sdram_ba;

    localparam StatusOK = 1;
    localparam StatusFailed = 0;

    // `define dataFromAddress(addr) ((addr))
    // `define dataFromAddress(addr) (!((addr)&8'b1))
    // `define dataFromAddress(addr) (~(addr))
    // `define dataFromAddress(addr) (8'h00)
    // `define dataFromAddress(addr) (8'hFF)

    logic[7:0] dataToWrite;
    assign dataToWrite = 8'd134;

    logic[7:0] addrToWrite;
    assign addrToWrite = 8'd20;

    logic needInit;
    logic status;

    // assign cmdTrigger = (cmdReady && status==StatusOK);
    // assign cmdWriteData = `dataFromAddress(cmdAddr);

    // assign ledRed = (status==StatusFailed);
    assign ledGreen = (status==StatusOK);

    // assign ledRed = (status==StatusFailed);
    // assign ledGreen = (doRead && !didRead);
    // assign ledGreen = !didRead;


    logic[3:0] ignored_sdram_a;
    logic[7:0] ignored_cmdReadData;
    logic[7:0] ignored_sdram_dq;

    SDRAMController sdramController(
        .clk(clk),
        .rst(rst),

        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr({2'b0, cmdAddr, 13'b0}),
        .cmdWrite(cmdWrite),
        .cmdWriteData({8'b0, cmdWriteData}),
        .cmdReadData({ignored_cmdReadData, cmdReadData}),
        .cmdReadDataValid(cmdReadDataValid),

        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a({sdram_a, ignored_sdram_a}),
        .sdram_cs_(),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_ldqm(sdram_dqm),
        .sdram_udqm(),
        .sdram_dq({ignored_sdram_dq, sdram_dq})
    );

    always @(posedge clk) begin
        if (rst) begin
            cmdTrigger <= 0;
            needInit <= 1;
            status <= StatusOK;
            ledRed <= 0;

        // Initialize memory to known values
        end else if (needInit) begin
            if (!cmdTrigger) begin
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= 0;
                cmdTrigger <= 1;
            end else if (cmdReady) begin
                if (cmdAddr < 8'hFF) begin
                    cmdAddr <= cmdAddr+1;
                    cmdWriteData <= cmdAddr;
                end else begin
                    // Next stage
                    needInit <= 0;
                    cmdTrigger <= 0;
                end
            end

        // end else if (status == StatusOK) begin
        end else begin
            // Disable cmdTrigger once the command is accepted
            if (cmdTrigger && cmdReady) begin
                cmdTrigger <= 0;
            end

            // Handle read data if available
            if (cmdReadDataValid) begin
                // Verify that the data read out is what we expect
                if (cmdReadData == dataToWrite)
                    status <= StatusOK;
                else
                    status <= StatusFailed;

            // Otherwise issue a new command
            end else if (doRead) begin
                // Prepare a command
                cmdWrite <= 0;
                cmdAddr <= addrToWrite;
                cmdTrigger <= 1;
                ledRed <= !ledRed;
            end
        end
    end




    // UART stuff
    reg transmit;
    reg [7:0] tx_byte;
    wire received;
    wire [7:0] rx_byte;
    wire is_receiving;
    wire is_transmitting;
    wire recv_error;

    uart #(
        .baud_rate(9600),                 // The baud rate in kilobits/s
        .sys_clk_freq(12000000)           // The master clock frequency
    )
    uart0(
        .clk(clk12mhz),                 // The master clock for this module
        .rst(rst),                      // Synchronous reset
        .rx(RS232_Rx_TTL),                // Incoming serial line
        .tx(RS232_Tx_TTL),                // Outgoing serial line
        .transmit(transmit),              // Signal to transmit
        .tx_byte(tx_byte),                // Byte to transmit
        .received(received),              // Indicated that a byte has been received
        .rx_byte(rx_byte),                // Byte received
        .is_receiving(is_receiving),      // Low when receive line is idle
        .is_transmitting(is_transmitting),// Low when transmit line is idle
        .recv_error(recv_error)           // Indicates error in receiving packet.
    );

    always @(posedge clk12mhz) begin
        if (received) begin
            tx_byte <= rx_byte+1;
            transmit <= 1;
        end else begin
            transmit <= 0;
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

module IcestickSDRAMTestSim(
    output logic        ledRed,
    output logic        ledGreen,

    output logic        sdram_clk,
    output logic        sdram_cke,
    // Use the high bits of `sdram_a` because we need A[10] for precharging to work!
    output logic[11:4]  sdram_a,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_dqm,
    inout logic[7:0]    sdram_dq
);

    logic clk;

    IcestickSDRAMTest icestickSDRAMTest(
        .clk12mhz(clk),
        .ledRed(ledRed),
        .ledGreen(ledGreen),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_a(sdram_a),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq)
    );

    logic[7:0] ignored_Dq;
    mt48lc8m16a2 sdram(
        .Clk(sdram_clk),
        .Dq({ignored_Dq, sdram_dq}),
        .Addr({sdram_a, 4'b1111}),
        .Ba(2'b0),
        .Cke(sdram_cke),
        .Cs_n(1'b0),
        .Ras_n(sdram_ras_),
        .Cas_n(sdram_cas_),
        .We_n(sdram_we_),
        .Dqm({sdram_dqm, sdram_dqm})
    );

    initial begin
        $dumpfile("IcestickSDRAMTest.vcd");
        $dumpvars(0, IcestickSDRAMTestSim);

        #10000000;
        $finish;
    end

    initial begin
        clk = 0;
        forever begin
            clk = !clk;
            #42;
        end
    end
endmodule

`endif
