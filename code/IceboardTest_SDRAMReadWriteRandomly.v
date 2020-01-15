//`define SYNTH
`timescale 1ns/1ps
`include "SDRAMController.v"

module Random8(
    input logic clk, rst,
    output logic[7:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=8: x^8 + x^6 + x^5 + x^4 + 1
        else q <= {q[6:0], q[8-1] ^ q[6-1] ^ q[5-1] ^ q[4-1]};
endmodule

module Random9(
    input logic clk, rst,
    output logic[8:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=9: x^9 + x^5 + 1
        else q <= {q[7:0], q[9-1] ^ q[5-1]};
endmodule

module Random23(
    input logic clk, rst,
    output logic[22:0] q
);
    always @(posedge clk)
        if (rst) q <= 1;
        // Feedback polynomial for N=23: x^23 + x^18 + 1
        else q <= {q[21:0], q[23-1] ^ q[18-1]};
endmodule

function reg[15:0] DataFromAddress;
    input reg[22:0] addr;
    DataFromAddress = {9'h1B5, addr[22:16]} ^ ~(addr[15:0]);
endfunction

module IceboardTest_SDRAMReadWriteRandomly(
    input logic         clk12mhz,
    
    output logic        ledRed,
    output logic        ledGreen,
    
    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_ldqm,
    output logic        sdram_udqm,
    inout logic[15:0]   sdram_dq
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
    
    localparam AddrWidth = 23;
    localparam AddrCount = 'h800000;
    localparam DataWidth = 16;
    localparam MaxEnqueuedReads = 10;
    localparam StatusOK = 1;
    localparam StatusFailed = 0;
    localparam DefaultVal = 16'hCAFE;
    
    localparam ModeIdle     = 2'h0;
    localparam ModeRead     = 2'h1;
    localparam ModeWrite    = 2'h2;
    
//    localparam ModeNop          = 3'h0;
//    localparam ModeRead         = 3'h1;
//    localparam ModeReadSeq      = 3'h2;
//    localparam ModeReadAll      = 3'h3;
//    localparam ModeWrite        = 3'h4;
//    localparam ModeWriteSeq     = 3'h5;
    
    `define dataFromAddress(addr) (addr[15:0])
//    `define dataFromAddress(addr) ({9'h1B5, addr[22:16]} ^ ~(addr[15:0]))
//    `define dataFromAddress(addr) 23'd0
    
    logic                   cmdReady;
    logic                   cmdTrigger;
    logic[AddrWidth-1:0]    cmdAddr;
    logic                   cmdWrite;
    logic[DataWidth-1:0]    cmdWriteData;
    logic[DataWidth-1:0]    cmdReadData;
    logic                   cmdReadDataValid;
    
    logic needInit;
    logic status;
    logic[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount;
    logic[(DataWidth*MaxEnqueuedReads)-1:0] expectedReadData;
    
    logic[DataWidth-1:0] currentExpectedReadData;
    assign currentExpectedReadData = expectedReadData[DataWidth-1:0];
    
    logic[1:0] mode;
    logic[AddrWidth-1:0] modeCounter;
    
    assign ledRed = (status!=StatusOK);
    
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
        .sdram_ldqm(sdram_ldqm),
        .sdram_udqm(sdram_udqm),
        .sdram_dq(sdram_dq)
    );
    
    logic[7:0] random8;
    Random8 random8Gen(.clk(clk), .rst(rst), .q(random8));
    
    logic[8:0] random9;
    Random9 random9Gen(.clk(clk), .rst(rst), .q(random9));
    
    logic[22:0] random23;
    Random23 random23Gen(.clk(clk), .rst(rst), .q(random23));
    
    always @(posedge clk) begin
        // Set default state
        cmdTrigger <= 0;
        cmdAddr <= 0;
        cmdWrite <= 0;
        cmdWriteData <= 0;
        
        if (rst) begin
            needInit <= 1;
            status <= StatusOK;
            enqueuedReadCount <= 0;
            mode <= ModeIdle;
            modeCounter <= 0;
        
        // Initialize memory to known values
        end else if (needInit) begin
            if (!cmdWrite) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= DefaultVal;
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
//                if (writeCounter < 'h7FFFFF) begin
                if (cmdAddr < 'hFF) begin
                    cmdTrigger <= 1;
                    cmdAddr <= cmdAddr+1;
                    cmdWrite <= 1;
                    cmdWriteData <= DefaultVal;
                
                end else begin
                    // Next stage
                    needInit <= 0;
                end
            end
        
        end else if (status == StatusOK) begin
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    enqueuedReadCount <= enqueuedReadCount-1;
                    
                    // Verify that the data read out is what we expect
                    if (cmdReadData!==DefaultVal && cmdReadData!==currentExpectedReadData) begin
                        status <= StatusFailed;
                    end
                    
                    expectedReadData <= expectedReadData >> DataWidth;
                
                // Something's wrong if we weren't expecting data and we got some
                end else status <= StatusFailed;
            end
            
            // Current command was accepted: prepare a new command
            if (cmdReady) begin
                case (mode)
                // We're idle: accept a new mode
                ModeIdle: begin
                    case (random8[2:0])
                    // Nop
                    0: begin
                    
                    end
                    
                    // Read
                    1,2: begin
                        cmdTrigger <= 1;
                        cmdAddr <= random23;
                        cmdWrite <= 0;
                        
                        expectedReadData <= expectedReadData|(DataFromAddress(random23)<<(DataWidth*enqueuedReadCount));
                        enqueuedReadCount <= enqueuedReadCount+1;
                        
                        mode <= ModeIdle;
                    end
                    
                    // Read sequential (start)
                    3,4: begin
                        cmdTrigger <= 1;
                        cmdAddr <= random23;
                        cmdWrite <= 0;
                        
                        expectedReadData <= expectedReadData|(DataFromAddress(random23)<<(DataWidth*enqueuedReadCount));
                        enqueuedReadCount <= enqueuedReadCount+1;
                        
                        mode <= ModeRead;
                        modeCounter <= random9;
                    end
                    
                    // Read all (start)
                    5: begin
                        cmdTrigger <= 1;
                        cmdAddr <= 0;
                        cmdWrite <= 0;
                        
                        expectedReadData <= expectedReadData|(DataFromAddress(0)<<(DataWidth*enqueuedReadCount));
                        enqueuedReadCount <= enqueuedReadCount+1;
                        
                        mode <= ModeRead;
                        modeCounter <= AddrCount-1;
                    end
                    
                    // Write
                    6: begin
                        cmdTrigger <= 1;
                        cmdAddr <= random23;
                        cmdWrite <= 1;
                        cmdWriteData <= DataFromAddress(random23);
                        
                        mode <= ModeIdle;
                    end
                    
                    // Write sequential (start)
                    7: begin
                        cmdTrigger <= 1;
                        cmdAddr <= random23;
                        cmdWrite <= 1;
                        
                        mode <= ModeWrite;
                        modeCounter <= random9;
                    end
                    endcase
                end
                
                // Read (continue)
                ModeRead: begin
                    if (modeCounter > 0) begin
                        cmdTrigger <= 1;
                        cmdAddr <= cmdAddr+1;
                        cmdWrite <= 0;
                    
                        expectedReadData <= expectedReadData|(DataFromAddress(cmdAddr+1)<<(DataWidth*enqueuedReadCount));
                        enqueuedReadCount <= enqueuedReadCount+1;
                        
                        modeCounter <= modeCounter-1;
                    
                    end else mode <= ModeIdle;
                end
                
                // Write (continue)
                ModeWrite: begin
                    if (modeCounter > 0) begin
                        cmdTrigger <= 1;
                        cmdAddr <= cmdAddr+1;
                        cmdWrite <= 1;
                        
                        modeCounter <= modeCounter-1;
                    
                    end else mode <= ModeIdle;
                end
                endcase
            end
        end
    end
endmodule

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

module IceboardTest_SDRAMReadWriteRandomlySim(
    output logic        ledRed,
    output logic        ledGreen,

    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic[1:0]   sdram_ba,
    output logic[11:0]  sdram_a,
    output logic        sdram_cs_,
    output logic        sdram_ras_,
    output logic        sdram_cas_,
    output logic        sdram_we_,
    output logic        sdram_ldqm,
    output logic        sdram_udqm,
    inout logic[15:0]   sdram_dq
);

    logic clk12mhz;

    IceboardTest_SDRAMReadWriteRandomly iceboardSDRAMTest(
        .clk12mhz(clk12mhz),
        .ledRed(ledRed),
        .ledGreen(ledGreen),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_ba(sdram_ba),
        .sdram_a(sdram_a),
        .sdram_cs_(sdram_cs_),
        .sdram_ras_(sdram_ras_),
        .sdram_cas_(sdram_cas_),
        .sdram_we_(sdram_we_),
        .sdram_ldqm(sdram_ldqm),
        .sdram_udqm(sdram_udqm),
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
        $dumpfile("IceboardTest_SDRAMReadWriteRandomly.vcd");
        $dumpvars(0, IceboardTest_SDRAMReadWriteRandomlySim);

        #10000000;
//        #2300000000;
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
