`timescale 1ns/1ps
`include "../GrayCode.v"

`define stringify(x) `"x```"
`define assert(cond) if (!(cond)) $error("Assertion failed: %s (%s:%0d)", `stringify(cond), `__FILE__, `__LINE__)

module AFIFO(
    input logic rclk,
    input logic r,
    output logic[Width-1:0] rd,
    output logic rempty,
    
    input logic wclk,
    input logic w,
    input logic[Width-1:0] wd,
    output logic wfull
);
    parameter Width = 12;
    parameter Size = 4; // Must be a power of 2
    localparam N = $clog2(Size)-1;
    
    logic[Width-1:0] mem[Size-1:0];
    logic[N:0] rbaddr, rgaddr; // Read addresses (binary, gray)
    logic[N:0] wbaddr, wgaddr; // Write addresses (binary, gray)
    
    // ====================
    // Read handling
    // ====================
    wire[N:0] rbaddrNext = rbaddr+1'b1;
    always @(posedge rclk)
        if (r & !rempty) begin
            rbaddr <= rbaddrNext;
            rgaddr <= (rbaddrNext>>1)^rbaddrNext;
        end
    
    logic rempty2;
    always @(posedge rclk, posedge aempty)
        if (aempty) {rempty, rempty2} <= 2'b11;
        else {rempty, rempty2} <= {rempty2, 1'b0};
    
    assign rd = mem[rbaddr];
    
    // ====================
    // Write handling
    // ====================
    wire[N:0] wbaddrNext = wbaddr+1'b1;
    always @(posedge wclk)
        if (w & !wfull) begin
            mem[wbaddr] <= wd;
            wbaddr <= wbaddrNext;
            wgaddr <= (wbaddrNext>>1)^wbaddrNext;
        end
    
    logic wfull2;
    always @(posedge wclk, posedge afull)
        if (afull) {wfull, wfull2} <= 2'b11;
        else {wfull, wfull2} <= {wfull2, 1'b0};
    
    // ====================
    // Async signal generation
    // ====================
    logic dir;
    wire aempty = (rgaddr==wgaddr) & !dir;
    wire afull = (rgaddr==wgaddr) & dir;
    wire dirset = (wgaddr[N]^rgaddr[N-1]) & ~(wgaddr[N-1]^rgaddr[N]);
    wire dirclr = ~(wgaddr[N]^rgaddr[N-1]) & (wgaddr[N-1]^rgaddr[N]);
    always @(posedge dirset, posedge dirclr)
        if (dirset) dir <= 1'b1;
        else dir <= 1'b0;
    
`ifdef SIM
    initial begin
        wfull = 0;
        wfull2 = 0;
        // logic[Width-1:0] rd
        // rempty
        // rempty2
        for (int i=0; i<Size; i++)
            mem[i] = 0;
        
        rbaddr = 0;
        rgaddr = 0;
        wbaddr = 0;
        wgaddr = 0;
        dir = 0;
    end
`endif
endmodule

`ifdef SIM

module AFIFOTestSim();
    logic wclk;
    logic w;
    logic[11:0] wd;
    logic wfull;
    logic rclk;
    logic r;
    logic[11:0] rd;
    logic rempty;
    
    logic[11:0] tmp;
    
    
    
    // task WaitUntilCommandAccepted;
    //     wait (!clk && cmdReady);
    //     wait (clk && cmdReady);
    //
    //     // Wait one time unit, so that changes that are made after aren't
    //     // sampled by the SDRAM controller on this clock edge
    //     #1;
    // endtask
    
    task Read(output logic[11:0] val);
        `assert(!rempty);
        
        // Get the current value that's available
        val = rd;
        $display("Read byte: %h", val);
        if (!rclk) #1; // Ensure rclk isn't transitioning on this step
        
        // Read a new value
        wait(!rclk);
        #1;
        r = 1;
        wait(rclk);
        #1;
        r = 0;
    endtask
    
    task Write(input logic[11:0] val);
        `assert(!wfull);
        
        if (!wclk) #1; // Ensure wclk isn't transitioning on this step
        wait(!wclk);
        #1;
        wd = val;
        w = 1;
        wait(wclk);
        #1;
        w = 0;
        
        $display("Wrote byte: %h", val);
    endtask
    
    task WaitUntilCanRead;
        wait(!rempty && !rclk);
    endtask
    
    task WaitUntilCanWrite;
        wait(!wfull && !wclk);
    endtask
    
    
    
    AFIFO afifo(.*);
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, AFIFOTestSim);
        
        wclk = 0;
        w = 0;
        wd = 0;
        rclk = 0;
        r = 0;
        
        // Write(12'hA);
        // Write(12'hB);
        // Write(12'hC);
        // Write(12'hD);
        //
        // Read(tmp);
        // Read(tmp);
        // Read(tmp);
        // Read(tmp);
        // Read(tmp);
        // Read(tmp);
        // Read(tmp);
       
        #10000000;
        //        #200000000;
        //        #2300000000;
        $finish;
    end
    
    initial begin
        int i;
        forever begin
            WaitUntilCanWrite;
            Write(i);
            i++;
        end
    end
    
    initial begin
        forever begin
            WaitUntilCanRead;
            Read(tmp);
        end
    end
    
    // wclk
    initial begin
        wclk = 0;
        forever begin
            wclk = !wclk;
            #42;
        end
    end
    
    // rclk
    initial begin
        #7;
        rclk = 0;
        forever begin
            rclk = !rclk;
            #3;
        end
    end
endmodule

`endif
