`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../SDRAMController.v"
`include "../mt48h32m16lf/mobile_sdr.v"

module Random9(
    input wire clk,
    output reg[8:0] q = 0
);
    always @(posedge clk)
        if (q == 0) q <= 1;
        // Feedback polynomial for N=9: x^9 + x^5 + 1
        else q <= {q[7:0], q[9-1] ^ q[5-1]};
endmodule

module Random16(
    input wire clk,
    output reg[15:0] q = 0
);
    always @(posedge clk)
        if (q == 0) q <= 1;
        // Feedback polynomial for N=16: x^16 + x^15 + x^13 + x^4 + 1
        else q <= {q[14:0], q[16-1] ^ q[15-1] ^ q[13-1] ^ q[4-1]};
endmodule

module Random25(
    input wire clk,
    output reg[24:0] q = 0
);
    always @(posedge clk)
        if (q == 0) q <= 1;
        // Feedback polynomial for N=25: x^25 + x^22 + 1
        else q <= {q[23:0], q[25-1] ^ q[22-1]};
endmodule

function [15:0] DataFromAddress;
    input [24:0] addr;
    DataFromAddress = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
//    DataFromAddress = addr[15:0];
endfunction

module Top(
    input wire          clk12mhz,
    
    output wire         ledFailed,
    output reg          ledDebug = 0,
    
    output wire         ram_clk,
    output wire         ram_cke,
    output wire[1:0]    ram_ba,
    output wire[12:0]   ram_a,
    output wire         ram_cs_,
    output wire         ram_ras_,
    output wire         ram_cas_,
    output wire         ram_we_,
    output wire[1:0]    ram_dqm,
    inout wire[15:0]    ram_dq
);
    localparam ClockFrequency = 100000000; // 100 MHz
    
    // 100 MHz clock
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
        .DIVR(0),
        .DIVF(66),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    localparam AddrWidth = 25;
    localparam AddrCount = 'h2000000;
    // localparam AddrCountLimit = AddrCount;
    localparam AddrCountLimit = AddrCount/1024; // 32k words
//    localparam AddrCountLimit = AddrCount/8192;
    localparam DataWidth = 16;
    localparam StatusOK = 0;
    localparam StatusFailed = 1;
    
    wire                  cmdReady;
    reg                   cmdTrigger = 0;
    reg[AddrWidth-1:0]    cmdAddr = 0;
    reg                   cmdWrite = 0;
    reg[DataWidth-1:0]    cmdWriteData = 0;
    wire[DataWidth-1:0]   cmdReadData;
    wire                  cmdReadDataValid;
    
    localparam MaxEnqueuedReads = 10;
    reg[(DataWidth*MaxEnqueuedReads)-1:0] expectedReadData = 0;
    reg[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount = 0;
    
    wire[DataWidth-1:0] currentExpectedReadData = expectedReadData[DataWidth-1:0];
    
    reg init = 0;
    reg status = StatusOK;
    
    assign ledFailed = (status!=StatusOK);
    
    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
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
    
    wire[8:0] random9;
    Random9 random9Gen(.clk(clk), .q(random9));
    
    wire[15:0] random16;
    Random16 random16Gen(.clk(clk), .q(random16));
    
    wire[AddrWidth-1:0] random25;
    Random25 random25Gen(.clk(clk), .q(random25));
    
    logic[AddrWidth-1:0] randomAddr;
    assign randomAddr = random25%AddrCountLimit;
    
    task Read(input logic[AddrWidth-1:0] addr);
        cmdTrigger <= 1;
        cmdAddr <= addr;
        cmdWrite <= 0;
        
        if (enqueuedReadCount >= MaxEnqueuedReads) begin
            `ifdef SIM
                $error("Too many enqueued reads");
            `endif
            
            status <= StatusFailed;
        end
        
        expectedReadData <= expectedReadData|(DataFromAddress(addr)<<(DataWidth*enqueuedReadCount));
        enqueuedReadCount <= enqueuedReadCount+1;
    endtask
    
    always @(posedge clk) begin
        // Set our default state if the current command was accepted
        if (cmdReady) cmdTrigger <= 0;
        
        // Initialize memory to known values
        if (!init) begin
            if (!cmdWrite) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= DataFromAddress(0);
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
                if (cmdAddr < AddrCountLimit-1) begin
//                if (cmdAddr < 'h7FFFFF) begin
//                if (cmdAddr < 'hFF) begin
                    cmdTrigger <= 1;
                    cmdAddr <= cmdAddr+1;
                    cmdWrite <= 1;
                    cmdWriteData <= DataFromAddress(cmdAddr+1);
                    
                    `ifdef SIM
                        if (!(cmdAddr % 'h1000)) begin
                            $display("Initializing memory: %h", cmdAddr);
                        end
                    `endif
                
                end else begin
                    // Next stage
                    init <= 1;
                    
                    // Kick off reading
                    Read(0);
                end
                
                // $display("Write: %h", cmdAddr);
            end
        
        end else if (status == StatusOK) begin
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    // $display("Read data: 0x%h", cmdReadData);
                    
                    // Verify that the data read out is what we expect
                    if (cmdReadData !== currentExpectedReadData) begin
                        `ifdef SIM
                            $error("Read invalid data (wanted: 0x%h/0x%h, got: 0x%h)", currentExpectedReadData, ~currentExpectedReadData, cmdReadData);
                        `endif
                        
                        status <= StatusFailed;
                    end
                    
                    expectedReadData <= expectedReadData >> DataWidth;
                    enqueuedReadCount <= enqueuedReadCount-1;
                
                // Something's wrong if we weren't expecting data and we got some
                end else begin
                    `ifdef SIM
                        $error("Received data when we didn't expect any");
                    `endif
                    
                    status <= StatusFailed;
                end
            end
            
            // Current command was accepted: prepare a new command
            else if (cmdReady) begin
                // A command was accepted, issue a new one
                $display("Enqueue read @ 0x%h", cmdAddr);
                
                Read((cmdAddr+1)&(AddrCountLimit-1));
                
                if (cmdAddr === 0) begin
                    ledDebug <= !ledDebug;
                end
            end
        end
    end
    
`ifdef SIM
    mobile_sdr sdram(
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
        // #1000000000;
        // $finish;
    end
`endif
endmodule
