`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../SDRAMController.v"

`ifdef SIM
`include "../mt48h32m16lf/mobile_sdr.v"
`endif

module Top(
    input wire          clk12mhz,
    
    output reg[7:0]     led = 0,
    
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
        
        DataFromAddr = 16'h00;
        
        // DataFromAddr = 8'hFF-addr[7:0];
        
        // DataFromAddr = 16'h1234;
        // DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
       // DataFromAddr = addr[15:0];
       // DataFromAddr = addr[24:9];
       // DataFromAddr = {1'b0, addr[14:0]};
       // DataFromAddr = {addr[14:0], 1'b1};
       
       // DataFromAddr = addr[15:0];
       
       // DataFromAddr = addr[15:0];
       
       // DataFromAddr = addr[24:9] ^ addr[14:0];
       
       // DataFromAddr = {addr[24:13], addr[10], addr[8], addr[6], addr[0]};
       
       // DataFromAddr = {15'b0, addr[15]^addr[14]^addr[13]^addr[12]^addr[11]^addr[10]^addr[ 9]^addr[ 8]^addr[ 7]^addr[ 6]^addr[ 5]^addr[ 4]^addr[ 3]^addr[ 2]^addr[ 1]^addr[ 0]};
    endfunction
    
    // 50 MHz clock
    //   icepll -i 12 -o 50 -m
    localparam ClockFrequency = 50000000; // 50 MHz
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
        .DIVR(0),
        .DIVF(66),
        .DIVQ(4),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    localparam AddrWidth = 25;
    localparam AddrCount = 'h2000000;
    localparam AddrCountLimit = 16;
    // localparam AddrCountLimit = AddrCount/1024; // 32k words
    // localparam AddrCountLimit = AddrCount/8192;
    // localparam AddrCountLimit = 8;
    localparam DataWidth = 16;
    
    localparam StatusOK             = 0;
    localparam StatusTooManyReads   = 1;
    localparam StatusInvalidData    = 2;
    localparam StatusUnexpectedData = 3;
    
    wire                  cmdReady;
    reg                   cmdTrigger = 0;
    reg[AddrWidth-1:0]    cmdAddr = 0;
    reg                   cmdWrite = 0;
    reg[DataWidth-1:0]    cmdWriteData = 0;
    wire[DataWidth-1:0]   cmdReadData;
    wire                  cmdReadDataValid;
    
    localparam MaxEnqueuedReads = 10;
    reg[(AddrWidth*MaxEnqueuedReads)-1:0] expectedReadAddr = 0;
    reg[$clog2(MaxEnqueuedReads)-1:0] enqueuedReadCount = 0;
    
    wire[AddrWidth-1:0] currentExpectedReadAddr = expectedReadAddr[AddrWidth-1:0];
    
    reg init = 0;
    reg[7:0] status = StatusOK /* synthesis syn_keep=1 */; // syn_keep is necessary to prevent Synplify optimization from removing -- "removing sequential instance ..."
    
    reg wrapped = 0;
    // assign led[7] = wrapped;
    // assign led[7:0] = status;
    
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
        
        expectedReadAddr <= (addr<<(AddrWidth*enqueuedReadCount))|expectedReadAddr;
        enqueuedReadCount <= enqueuedReadCount+1;
    end endtask
    
    always @(posedge clk) begin
        // Set our default state if the current command was accepted
        if (cmdReady) cmdTrigger <= 0;
        
        // Initialize memory to known values
        if (!init) begin
            if (!cmdWrite) begin
                cmdTrigger <= 1;
                cmdAddr <= 0;
                cmdWrite <= 1;
                cmdWriteData <= DataFromAddr(0);
                
                led <= 8'h55;
            
            // The SDRAM controller accepted the command, so transition to the next state
            end else if (cmdReady) begin
                if (cmdAddr < AddrCountLimit-1) begin
//                if (cmdAddr < 'h7FFFFF) begin
//                if (cmdAddr < 'hFF) begin
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
                    // Next stage
                    init <= 1;
                    
                    // Kick off reading
                    Read(0);
                    
                    led <= 8'h00;
                end
                
                // $display("Write: %h", cmdAddr);
            end
        
        end else if (status == StatusOK) begin
            // Handle read data if available
            if (cmdReadDataValid) begin
                if (enqueuedReadCount > 0) begin
                    // $display("Read data: 0x%h", cmdReadData);
                    
                    // Verify that the data read out is what we expect
                    if (cmdReadData != DataFromAddr(currentExpectedReadAddr)) begin
                        `ifdef SIM
                            $error("Read invalid data (wanted: 0x%h/0x%h, got: 0x%h)", DataFromAddr(currentExpectedReadAddr), ~DataFromAddr(currentExpectedReadAddr), cmdReadData);
                        `endif
                        
                        status <= StatusInvalidData;
                        
                        led <= currentExpectedReadAddr;
                        // led <= 8'b11110000;
                    end else begin
                        $display("Read expected data from addr 0x%x: 0x%x", currentExpectedReadAddr, DataFromAddr(currentExpectedReadAddr));
                    end
                    
                    
                    // // 16'h2BE
                    // if ((cmdReadData|16'h2BE) != (currentExpectedReadData|16'h2BE)) begin
                    //     `ifdef SIM
                    //         $error("Read invalid data (wanted: 0x%h/0x%h, got: 0x%h)", currentExpectedReadData, ~currentExpectedReadData, cmdReadData);
                    //     `endif
                    //
                    //     status <= StatusInvalidData;
                    // end
                    
                    expectedReadAddr <= expectedReadAddr >> AddrWidth;
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
                `ifdef SIM
                    $display("Enqueue read @ 0x%h", cmdAddr);
                `endif
                
                Read((cmdAddr+1)&(AddrCountLimit-1));
                
                if (cmdAddr == 0) begin
                    wrapped <= !wrapped;
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
    
    // initial begin
    //     $dumpfile("top.vcd");
    //     $dumpvars(0, Top);
    //     // #1000000000;
    //     // $finish;
    // end
`endif
endmodule
