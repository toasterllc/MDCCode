`timescale 1ns/1ps
`include "SDRAMController.v"
`include "4062mt48lc8m16a2/mt48lc8m16a2.v"

// Verify constant values with yosys:
//   yosys -p "read_verilog -dump_rtlil -formal -sv Top.sv"

// Run simulation using Icarus Verilog (generates waveform file 'TopSim.vcd'):
//   rm -f TopSim.vvp ; iverilog -o TopSim.vvp -g2012 TopSim.v ; ./TopSim.vvp

// Run timing analysis
//  icetime -tmd hx1k Top.asc

module TestSDRAMSim();
    logic clk;
    logic delayed_clk;
    logic rst;
    
    logic cmdReady;
    logic cmdTrigger;
    logic[22:0] cmdAddr;
    logic cmdWrite;
    logic[15:0] cmdWriteData;
    logic[15:0] cmdReadData;
    logic cmdReadDataValid;
    
    logic sdram_clk;
    logic sdram_cke;
    logic[1:0] sdram_ba;
    logic[11:0] sdram_a;
    logic sdram_cs_;
    logic sdram_ras_;
    logic sdram_cas_;
    logic sdram_we_;
    logic sdram_ldqm;
    logic sdram_udqm;
    inout logic[15:0] sdram_dq;
    
    SDRAMController sdramController(
        .clk(delayed_clk),
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
    
    mt48lc8m16a2 ram(
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
    
    task DelayClocks(input integer n);
        #(10*n);
        // repeat (n) @(posedge clk);
    endtask
    
    logic go;
    always @(posedge delayed_clk) begin
        if (rst) go = 0;  // reset register
        else if (cmdReady) #5 go = 1;
    end
    
    always @(posedge delayed_clk) begin
        if (rst) begin
            cmdAddr <= 0;
            // cmdWrite <= 0;
        end else if (cmdReady & cmdTrigger) begin
            cmdAddr <= cmdAddr+1;
            // cmdWrite <= !cmdWrite;
        end
    end
    
    assign cmdWriteData = ~cmdAddr;
    
    initial begin
        $dumpfile("TestSDRAMSim.vcd");
        $dumpvars(0, TestSDRAMSim);
        
        cmdWrite = 0;
        // cmdWriteData = 0;
        cmdTrigger = 0;
        
        // Reset
        rst = 1;
        DelayClocks(2);
        rst = 0;
        DelayClocks(1);
        
        // Wait until our RAM is ready
        wait(go);
        
        // Test writes
        cmdWrite = 1;
        cmdTrigger = 1;
        DelayClocks(500);
        
        // Test reads
        cmdAddr = 0;
        cmdWrite = 0;
        cmdTrigger = 1;
        DelayClocks(4);
        repeat (500) begin
            DelayClocks(1);
            $display("%x", cmdReadData);
        end
        
        DelayClocks(500);
        
        
        
        // // Test single write
        // cmdWrite = 1;
        // cmdWriteData = 16'hABCD;
        // cmdTrigger = 1;
        // DelayClocks(1);
        // cmdTrigger = 0;
        
        // DelayClocks(10);
        
        // repeat (10) begin
        //     cmdWrite = 1;
        //     cmdTrigger = 1;
        //
        //     DelayClocks(1);
        //
        //     cmdTrigger = 0;
        //     DelayClocks(1552);
        //
        //     // Test mass write
        //
        //     // cmdWriteData = 16'hABCD;
        //
        //
        // end
        
        // // Test single read
        // cmdWrite = 0;
        // cmdTrigger = 1;
        // DelayClocks(1);
        // cmdTrigger = 0;
        
        // // Test mass read
        // cmdWrite = 0;
        // cmdTrigger = 1;
        
        // Test mass write
        cmdWrite = 1;
        cmdTrigger = 1;
        
        DelayClocks(30000); // Wait 300us
        
        $finish;
    end
    
    // Run clock
    initial begin
        clk = 0;
        forever begin
            #5;
            clk = !clk;
        end
    end

    always @(clk) begin
        #1 delayed_clk = clk;
    end
endmodule
