`include "../SDRAMController.v"
`include "../mt48h32m16lf/mobile_sdr.v"

`timescale 1ns/1ps

`define stringify(x) `"x```"
`define assert(cond) if (!(cond)) $error("Assertion failed: %s (%s:%0d)", `stringify(cond), `__FILE__, `__LINE__)
`define dataFromAddress(addr) ({9'h1B5, addr[22:16]} ^ ~(addr[15:0]))

function reg[15:0] DataFromAddress;
    input reg[22:0] addr;
    DataFromAddress = {9'h1B5, addr[22:16]} ^ ~(addr[15:0]);
endfunction

module Top();
    localparam ClockFrequency = 100000000;
    localparam AddrWidth = 25; // Width of addresses
    localparam AddrCount = 'h8000; // Number of addresses
    localparam UnknownVal = {16{'x}};
    
    reg clk;
    reg rst;
    
    reg cmdReady;
    
    reg cmdTrigger;
    reg cmdWrite;
    reg[AddrWidth-1:0] cmdAddr;
    reg[15:0] cmdWriteData;
    
    reg[15:0] cmdReadData;
    reg cmdReadDataValid;
    
    reg[AddrCount-1:0] writtenAddrs; // Addresses that have been written to
    reg[15:0] expectedDataQueue[$]; // The queue of data that we expect to read from the SDRAM
    
    logic       ram_clk;
    logic       ram_cke;
    logic[1:0]  ram_ba;
    logic[12:0] ram_a;
    logic       ram_cs_;
    logic       ram_ras_;
    logic       ram_cas_;
    logic       ram_we_;
    logic[1:0]  ram_dqm;
    wire[15:0] ram_dq;
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
    
    task WaitUntilCommandAccepted;
        wait (!clk && cmdReady);
        wait (clk && cmdReady);
        
        // Wait one time unit, so that changes that are made after aren't
        // sampled by the SDRAM controller on this clock edge
        #1;
    endtask
    
    task Write(input [22:0] addr, input [15:0] val);
        cmdTrigger = 1;
        cmdWrite = 1;
        cmdAddr = addr;
        cmdWriteData = val;
        WaitUntilCommandAccepted;
        cmdTrigger = 0;
    endtask
    
    task ReadAsync(input [22:0] addr, input [15:0] val);
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
//        $dumpfile("top.vcd");
//        $dumpvars(0, Iceboard_SimpleReadWriteSim);
        
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
            
           // $display("Read data; wanted: 0x%h, got: 0x%h", expectedData, cmdReadData);
            if (expectedData !== cmdReadData)
                $error("Read invalid data (wanted: 0x%h, got: 0x%h)", expectedData, cmdReadData);
        end
    end
    
    // Clock
    initial begin
        clk = 0;
        forever begin
            clk = !clk;
            #5;
        end
    end
    
    // initial begin
    //    $dumpfile("top.vcd");
    //    $dumpvars(0, Top);
    //    #1000000000;
    //    $finish;
    // end
endmodule
