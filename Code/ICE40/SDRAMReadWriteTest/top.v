`include "../Util/Util.v"
`include "../Util/SDRAMController.v"
`include "../Util/Delay.v"

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          clk24mhz,
    
    output wire[3:0]    led,
    
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
    function [15:0] DataFromAddr;
        input [24:0] addr;
        DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
        // DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
    endfunction
    
    // 24 MHz clock
    localparam ClkFreq = 24000000;
    
    
    // wire clk = clk24mhz;
    // Delay #(
    //     .Count(32)
    // ) Delay(
    //     .in(clk),
    //     .out(ram_clk)
    // );
    
    
    wire ram_clk = clk24mhz;
    Delay #(
        .Count(1)
    ) Delay(
        .in(clk24mhz),
        .out(clk)
    );
    
    
    localparam AddrWidth = 25;
    localparam AddrCount = 'h2000000;
    localparam AddrCountLimit = AddrCount;
    // localparam AddrCountLimit = 'h10000;
    // localparam AddrCountLimit = AddrCount/8192;
    
    
    // localparam AddrCountLimit = AddrCount/512;
    // localparam AddrCountLimit = AddrCount/1024; // 32k words
    // localparam AddrCountLimit = AddrCount/8192;
    localparam DataWidth = 16;
    
    localparam StatusStart          = 0;
    localparam StatusInit           = 1;
    localparam StatusUnderway       = 2;
    localparam StatusTooManyReads   = 3;
    localparam StatusInvalidData    = 4;
    localparam StatusUnexpectedData = 5;
    
    wire                  cmdReady;
    reg                   cmdTrigger = 0;
    reg[AddrWidth-1:0]    cmdAddr = 0;
    reg                   cmdWrite = 0;
    reg[DataWidth-1:0]    cmdWriteData = 0;
    wire[DataWidth-1:0]   cmdReadData;
    wire                  cmdReadDataValid;
    
    localparam MaxEnqueuedReads = 10;
    reg[(AddrWidth*MaxEnqueuedReads)-1:0] readAddr = 0;
    reg[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount = 0;
    
    wire[AddrWidth-1:0] currentReadAddr = readAddr[AddrWidth-1:0];
    wire[DataWidth-1:0] expectedReadData = DataFromAddr(currentReadAddr);
    
    reg[2:0] status = StatusStart;
    assign led[2:0] = status;
    
    reg wrapped = 0;
    assign led[3] = wrapped;
    
    SDRAMController #(
        .ClkFreq(ClkFreq)
    ) sdramController(
        .clk(clk),
        
        .cmdReady(cmdReady),
        .cmdTrigger(cmdTrigger),
        .cmdAddr(cmdAddr),
        .cmdWrite(cmdWrite),
        .cmdWriteData(cmdWriteData),
        .cmdReadData(cmdReadData),
        .cmdReadDataValid(cmdReadDataValid),
        
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
    
    
    
    
    
    
    
    
    
    
    
    task Read(input [AddrWidth-1:0] addr); begin
        cmdTrigger <= 1;
        cmdAddr <= addr;
        cmdWrite <= 0;
        
        if (enqueuedReadCount >= MaxEnqueuedReads) begin
            `ifdef SIM
                $error("Too many enqueued reads");
            `endif
            
            status <= StatusTooManyReads;
        end
        
        readAddr <= (addr<<(AddrWidth*enqueuedReadCount))|readAddr;
        enqueuedReadCount <= enqueuedReadCount+1;
    end endtask
    
    always @(posedge clk) begin
        // Set our default state if the current command was accepted
        if (cmdReady) cmdTrigger <= 0;
        
        // Initialize memory to known values
        if (status == StatusStart) begin
            cmdTrigger <= 1;
            cmdAddr <= 0;
            cmdWrite <= 1;
            cmdWriteData <= DataFromAddr(0);
            
            status <= StatusInit;
        
        end else if (status == StatusInit) begin
            // The SDRAM controller accepted the command, so transition to the next state
            if (cmdReady) begin
                if (cmdAddr < AddrCountLimit-1) begin
                    cmdTrigger <= 1;
                    cmdAddr <= cmdAddr+1;
                    cmdWrite <= 1;
                    cmdWriteData <= DataFromAddr(cmdAddr+1);
                    
                    `ifdef SIM
                        if (!(cmdAddr % 'h1000)) begin
                            $display("Initializing memory: %h", cmdAddr);
                        end
                    `endif
                
                end else begin
                    // Kick off reading
                    Read(0);
                    
                    // Next stage
                    status <= StatusUnderway;
                end
                
                // $display("Write: %h", cmdAddr);
            end
        
        end else if (status == StatusUnderway) begin
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    // $display("Read data: 0x%h", cmdReadData);
                    
                    // Verify that the data read out is what we expect
                    if (cmdReadData != expectedReadData) begin
                        `ifdef SIM
                            $error("Read invalid data (expected: 0x%h, got: 0x%h)", expectedReadData, cmdReadData);
                        `endif
                        
                        status <= StatusInvalidData;
                        
                    end else begin
                        `ifdef SIM
                            $display("Read expected data from addr 0x%x: 0x%x", currentReadAddr, DataFromAddr(currentReadAddr));
                        `endif
                    end
                    
                    readAddr <= readAddr >> AddrWidth;
                    enqueuedReadCount <= enqueuedReadCount-1;
                
                // Something's wrong if we weren't expecting data and we got some
                end else begin
                    `ifdef SIM
                        $error("Received data when we didn't expect any");
                    `endif
                    
                    status <= StatusUnexpectedData;
                end
            end
            
            // Current command was accepted: prepare a new command
            else if (cmdReady) begin
                // A command was accepted, issue a new one
                // `ifdef SIM
                //     $display("Enqueue read @ 0x%h", cmdAddr);
                // `endif
                
                Read((cmdAddr+1)&(AddrCountLimit-1));
                
                if (cmdAddr == 0) begin
                    wrapped <= !wrapped;
                end
            end
        end
    end
    
`ifdef SIM

`endif
endmodule




`ifdef SIM
module Testbench();
    reg clk24mhz = 0;
    wire[3:0] led;
    wire ram_clk;
    wire ram_cke;
    wire[1:0] ram_ba;
    wire[12:0] ram_a;
    wire ram_cs_;
    wire ram_ras_;
    wire ram_cas_;
    wire ram_we_;
    wire[1:0] ram_dqm;
    wire[15:0] ram_dq;
    Top Top(.*);
    
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
        $dumpvars(0, Testbench);
    end
    
    initial begin
        #100000000;
        `Finish;
    end
    
    initial begin
        forever begin
            clk24mhz = 0;
            #21;
            clk24mhz = 1;
            #21;
        end
    end
endmodule
`endif


