//`define SYNTH
`timescale 1ns/1ps
`include "SDRAMController.v"

`ifndef SYNTH

`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

`define Stringify(x) `"x```"
`define assert(cond) if (!cond) $error("Assertion failed: %s (%s:%0d)", `Stringify(cond), `__FILE__, `__LINE__)
`define dataFromAddress(addr) ({9'h1B5, addr[22:16]} ^ ~(addr[15:0]))

function reg[15:0] DataFromAddress;
    input reg[22:0] addr;
    DataFromAddress = {9'h1B5, addr[22:16]} ^ ~(addr[15:0]);
endfunction

module IceboardTest_SimpleReadWriteSim(
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
    localparam AddrWidth = 23; // Width of addresses
    localparam AddrCount = 'h800000; // Number of addresses
    localparam UnknownVal = {16{'x}};
    
    logic clk;
    logic rst;
    
    logic cmdReady;
    
    logic cmdTrigger;
    logic cmdWrite;
    logic[AddrWidth-1:0] cmdAddr;
    logic[15:0] cmdWriteData;
    
    logic[15:0] cmdReadData;
    logic cmdReadDataValid;
    
    logic[AddrCount-1:0] writtenAddrs; // Addresses that have been written to
    logic[15:0] expectedDataQueue[$]; // The queue of data that we expect to read from the SDRAM
    
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
    
    task WaitUntilCommandAccepted;
        wait (!clk && cmdReady);
        wait (clk && cmdReady);
        
        // Wait one time unit, so that changes that are made after aren't
        // sampled by the SDRAM controller on this clock edge
        #1;
    endtask
    
    task Write(input logic[22:0] addr, input logic[15:0] val);
        cmdTrigger = 1;
        cmdWrite = 1;
        cmdAddr = addr;
        cmdWriteData = val;
        WaitUntilCommandAccepted;
        cmdTrigger = 0;
    endtask
    
    task ReadAsync(input logic[22:0] addr, input logic[15:0] val);
        cmdTrigger = 1;
        cmdWrite = 0;
        cmdAddr = addr;
        WaitUntilCommandAccepted;
        cmdTrigger = 0;
        
        expectedDataQueue.push_back(val);
    endtask
    
    task WaitForReadData;
        wait (!clk && cmdReadDataValid);
        wait (clk && cmdReadDataValid);
    endtask
    
    // Reset
    initial begin
//        $dumpfile("IceboardTest_SimpleReadWrite.vcd");
//        $dumpvars(0, IceboardTest_SimpleReadWriteSim);
        
        rst = 1;
        cmdTrigger = 0;
        cmdWrite = 0;
        cmdAddr = 0;
        cmdWriteData = 0;
        writtenAddrs = 0;
        
        #10;
        rst = 0;
        
        //#1000000;
        //$finish;
    end
    
    // Issue commands
    initial begin
        wait (clk && cmdReady);
        #1;
        
        forever begin
            integer scheme;
            integer count;
            logic[AddrWidth-1:0] randomAddr;
            
            scheme = $urandom%4;
            count = $urandom%2048;
            randomAddr = $urandom%AddrCount;
            
            // Confine randomAddr so we have a better chance of reading/writing from a previously-accessed address
            randomAddr = randomAddr%(1024*16);
            
            case (scheme)
            // Read
            0: begin
                logic[AddrWidth-1:0] addr;
                addr = randomAddr;
                
                $display("Read: 0x%h", addr);
                ReadAsync(addr, (writtenAddrs[addr] ? DataFromAddress(addr) : UnknownVal));
            end
            
            // Write
            1: begin
                logic[AddrWidth-1:0] addr;
                addr = randomAddr;
                
                $display("Write: 0x%h", addr);
                Write(addr, DataFromAddress(addr));
                writtenAddrs[addr] = 1;
            end
            
            // Read sequential
            2: begin
                integer i;
                $display("Read seq: 0x%h[%h]", randomAddr, count);
                for (i=0; i<count; i++) begin
                    logic[AddrWidth-1:0] addr;
                    addr = randomAddr+i;
                    
                    ReadAsync(addr, (writtenAddrs[addr] ? DataFromAddress(addr) : UnknownVal));
                end
            end
            
            // Write sequential
            3: begin
                integer i;
                $display("Write seq: 0x%h[%h]", randomAddr, count);
                for (i=0; i<count; i++) begin
                    logic[AddrWidth-1:0] addr;
                    addr = randomAddr+i;
                    
                    //$display("Write seq[%0d]: 0x%h[%h]", i, randomAddr, count);
                    
                    Write(addr, DataFromAddress(addr));
                    writtenAddrs[addr] = 1;
                end
            end
            endcase
        end
    end
    
//    // Issue commands
//    initial begin
//        logic[23:0] addr; // width=24 so we can detect overflow
//        
//        wait (clk && cmdReady);
//        #1;
//        
//        // Initialize our memory
//        for (addr=0; addr<'h800000; addr++) begin
//            Write(addr, DataFromAddress(addr));
//            if (!(addr % 'h1000)) begin
//                $display("Initialized 0x%h", addr);
//            end
//        end
//        
////        $display("Finished initializing memory");
//        
////        forever begin
////            logic shouldWrite;
////            
////            Write('h000000, DataFromAddress('h000000));
////            Write('h000001, DataFromAddress('h000001));
////            
////            ReadAsync('h000000, DataFromAddress('h000000));
////            ReadAsync('h000001, DataFromAddress('h000001));
////            
////            shouldWrite = $urandom%2;
////        end
//    end
    
    // Verify read data
    initial begin
        forever begin
            logic[15:0] expectedData;
            
            // Wait for data to become available
            WaitForReadData;
            
            // Verify that we expected incoming data
            if (expectedDataQueue.size() == 0)
                $error("Received data when we didn't expect any");
            
            expectedData = expectedDataQueue.pop_front();
            
//            $display("Read data; wanted: 0x%h, got: 0x%h", expectedData, cmdReadData);
            if (expectedData !== cmdReadData)
                $error("Read invalid data (wanted: 0x%h, got: 0x%h)", expectedData, cmdReadData);
        end
    end
    
    // Clock
    initial begin
        clk = 0;
        forever begin
            clk = !clk;
            #42;
        end
    end
endmodule

`endif
