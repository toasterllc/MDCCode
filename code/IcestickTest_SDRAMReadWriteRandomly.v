`define SYNTH
`timescale 1ns/1ps
`include "uart.v"
`include "SDRAMController.v"

module RandomNumberGenerator(
    input logic clk,
    input logic rst,
    output logic[7:0] q
);
    parameter SEED = 8'd1;
    always @(posedge clk)
    if (rst) q <= SEED; // anything except zero
     // polynomial for maximal LFSR
    else q <= {q[6:0], q[7] ^ q[5] ^ q[4] ^ q[3]};
endmodule

module Scrambler(
    input logic[7:0] d,
    output logic[7:0] q
);
	assign q[0] = d[5];
	assign q[1] = d[2];
	assign q[2] = d[1];
	assign q[3] = d[3];
	assign q[4] = d[4];
	assign q[5] = d[0];
	assign q[6] = d[7];
	assign q[7] = d[6];
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
    inout logic[7:0]    sdram_dq
);
    localparam ClockFrequency = 12000000;
    
    `define RESET_BIT 26

    logic[`RESET_BIT:0] clkDivider;

    `ifndef SYNTH
    initial clkDivider = 0;
    `endif
    
    always @(posedge clk12mhz) clkDivider <= clkDivider+1;
    
    logic clk;
    assign clk = clk12mhz;
    
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
    
    `define dataFromAddress(addr) (~(addr))
    
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
        .sdram_udqm(),
        .sdram_ldqm(sdram_dqm),
        .sdram_dq({ignored_sdram_dq, sdram_dq})
    );
    
    logic[7:0] randomBits;
    RandomNumberGenerator #(.SEED(22)) rng(.clk(clk), .rst(rst), .q(randomBits));
    logic shouldWrite;
    assign shouldWrite = randomBits[0] || enqueuedReadCount>=3;
	
    logic[7:0] readCounter;
    logic[7:0] scrambledReadAddr;
	Scrambler readAddrScrambler(.d(readCounter), .q(scrambledReadAddr));
	
	logic[7:0] writeCounter;
    logic[7:0] scrambledWriteAddr;
	Scrambler writeAddrScrambler(.d(writeCounter), .q(scrambledWriteAddr));
    
    always @(posedge clk) begin
        if (rst) begin
            cmdTrigger <= 0;
            needInit <= 1;
            status <= StatusOK;
            enqueuedReadAddr <= 0;
            enqueuedReadCount <= 0;
			readCounter <= 0;
			writeCounter <= 0;
        
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
        
        //end else begin
        end else if (status == StatusOK) begin
            // Prevent duplicate commands
            if (cmdTrigger && cmdReady) begin
                cmdTrigger <= 0;
            end
            
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    enqueuedReadCount <= enqueuedReadCount-1;
                    
//					if (enqueuedReadAddr[7:0] == 8'd126) begin
//						status <= StatusFailed;
//					end else begin
	                    // Verify that the data read out is what we expect
	                    if (cmdReadData == `dataFromAddress(enqueuedReadAddr[7:0]))
	                        status <= StatusOK;
	                    else
	                        status <= StatusFailed;
//					end
                    
                    enqueuedReadAddr <= enqueuedReadAddr>>8;
                
                // Something's wrong if we weren't expecting data and we got some
                end else status <= StatusFailed;
            
            // Otherwise issue a new command
            end else if (!cmdTrigger || (cmdTrigger && cmdReady)) begin
                // Prepare a command
                cmdWrite <= shouldWrite;
				
				if (shouldWrite) begin
					cmdAddr <= scrambledWriteAddr;
					writeCounter <= writeCounter+1;
				end else begin
					cmdAddr <= scrambledReadAddr;
					readCounter <= readCounter+1;
				end
                
                cmdTrigger <= 1;
                
                // If we're writing, load the data into cmdWriteData
                if (shouldWrite) cmdWriteData <= `dataFromAddress(scrambledWriteAddr);
                // If we're reading, remember the address that we're expecting data from
                else begin
                    enqueuedReadAddr <= enqueuedReadAddr|(scrambledReadAddr<<(8*enqueuedReadCount));
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
