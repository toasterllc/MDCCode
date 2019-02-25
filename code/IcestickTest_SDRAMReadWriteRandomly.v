// `define SYNTH
`timescale 1ns/1ps
`include "uart.v"
`include "SDRAMController.v"

module RandomNumberGenerator(
    input logic clk,
    input logic rst,
    output logic[7:0] q
);
    logic[7:0] counter;
    
    parameter SEED = 8'd1;
    always @(posedge clk)
    if (rst) begin
        q <= SEED; // anything except zero
        counter <= 0;
     // polynomial for maximal LFSR
    end else begin
        q <= (counter>=8'h42 && counter<=8'h52 ? 8'h42 : {q[6:0], q[7] ^ q[5] ^ q[4] ^ q[3]});
        counter <= counter+1;
    end
endmodule

module IcestickTest_SDRAMReadWriteRandomly(
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
    // localparam ClockFrequency = 1500000;
    localparam ClockFrequency = 12000000;
    
    // `define RESET_BIT 26
    //
    // logic[`RESET_BIT:0] clkDivider;
    //
    // `ifndef SYNTH
    // initial clkDivider = 0;
    // `endif
    
    // always @(posedge clk12mhz) clkDivider <= clkDivider+1;
    
    logic clk;
    assign clk = clk12mhz;//clkDivider[0];
    
    // Generate our own reset signal
    // This relies on the fact that the ice40 FPGA resets flipflops to 0 at power up
    logic[12:0] rstCounter;
    logic rst;
    logic lastBit;
    assign rst = !rstCounter[$size(rstCounter)-1];
    always @(posedge clk) begin
        if (rst) begin
            rstCounter <= rstCounter+1;
        end
        
        // // Generate a reset every time clkDivider[`RESET_BIT] goes 0->1
        // lastBit <= clkDivider[`RESET_BIT];
        // if (clkDivider[`RESET_BIT] && !lastBit) begin
        //     rstCounter <= 0;
        // end
    end
    assign ledGreen = rst;
    
    `ifndef SYNTH
    initial rstCounter = 0;
    `endif
    
    logic               cmdReady;
    logic               cmdTrigger;
    logic[20:13]        cmdAddr;
    logic               cmdWrite;
    logic[7:0]          cmdWriteData;
    logic[7:0]          cmdReadData;
    logic               cmdReadDataValid;
    
    logic[1:0]          sdram_ba;
    
    logic[3:0]          ignored_sdram_a;
    logic[7:0]          ignored_cmdReadData;
    logic[7:0]          ignored_sdram_dq;
    
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    
    `define dataFromAddress(addr) (addr) //(~(addr))
    
    logic needInit;
    logic status;
    logic[23:0] enqueuedReadAddr;
    logic[2:0] enqueuedReadCount;
    
    assign ledRed = (status!=StatusOK);
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
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
    
    logic[7:0] randomBits;
    RandomNumberGenerator #(.SEED(22)) rng(.clk(clk), .rst(rst), .q(randomBits));
    
    logic[7:0] randomAddr;
    RandomNumberGenerator #(.SEED(99)) rng2(.clk(clk), .rst(rst), .q(randomAddr));
    
    logic shouldWrite;
    assign shouldWrite = randomBits[0] || enqueuedReadCount>=3;
    
    always @(posedge clk) begin
        if (rst) begin
            cmdTrigger <= 0;
            needInit <= 1;
            status <= StatusOK;
            enqueuedReadAddr <= 0;
            enqueuedReadCount <= 0;
        
        // Initialize memory to known values
        end else if (needInit) begin
            if (!cmdTrigger) begin
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= `dataFromAddress(0);
                cmdTrigger <= 1;
            end else if (cmdReady) begin
                if (cmdAddr < 8'hFF) begin
                    cmdAddr <= cmdAddr+1;
                    cmdWriteData <= `dataFromAddress(cmdAddr+1);
                end else begin
                    // Next stage
                    needInit <= 0;
                    cmdTrigger <= 0;
                end
            end
        
        end else begin
        // end else if (status == StatusOK) begin
            // Prevent duplicate commands
            if (cmdTrigger && cmdReady) begin
                cmdTrigger <= 0;
            end
            
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    enqueuedReadCount <= enqueuedReadCount-1;
                    
                    // Verify that the data read out is what we expect
                    if (cmdReadData == `dataFromAddress(enqueuedReadAddr[7:0]))
                        status <= StatusOK;
                    else
                        status <= StatusFailed;
                    
                    enqueuedReadAddr <= enqueuedReadAddr>>8;
                
                // Something's wrong if we weren't expecting data and we got some
                end else status <= StatusFailed;
            
            // Otherwise issue a new command
            end else if (!cmdTrigger || (cmdTrigger && cmdReady)) begin
                // Prepare a command
                cmdWrite <= shouldWrite;
                cmdAddr <= randomAddr;
                cmdTrigger <= 1;
                
                // If we're writing, load the data into cmdWriteData
                if (shouldWrite) cmdWriteData <= `dataFromAddress(randomAddr);
                // If we're reading, remember the address that we're expecting data from
                else begin
                    enqueuedReadAddr <= enqueuedReadAddr|(randomAddr<<(8*enqueuedReadCount));
                    enqueuedReadCount <= enqueuedReadCount+1;
                end
            end
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

module IcestickTest_SDRAMReadWriteRandomlySim(
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

    logic clk12mhz;

    IcestickTest_SDRAMReadWriteRandomly icestickSDRAMTest(
        .clk12mhz(clk12mhz),
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
        .Addr({sdram_a, 4'b0111}),
        .Ba(2'b0),
        .Cke(sdram_cke),
        .Cs_n(1'b0),
        .Ras_n(sdram_ras_),
        .Cas_n(sdram_cas_),
        .We_n(sdram_we_),
        .Dqm({sdram_dqm, sdram_dqm})
    );

    initial begin
        $dumpfile("IcestickTest_SDRAMReadWriteRandomly.vcd");
        $dumpvars(0, IcestickTest_SDRAMReadWriteRandomlySim);

        #10000000;
        $finish;
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
