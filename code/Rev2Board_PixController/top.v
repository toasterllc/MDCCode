`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
`include "../SDRAMController.v"

module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0,
    
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
    // ====================
    // Clock PLL (15.938 MHz)
    // ====================
    localparam ClockFrequency = 15938000;
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
        .DIVR(0),
        .DIVF(84),
        .DIVQ(6),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    
    
    
    // ====================
    // SDRAM controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;
    
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;
    wire[RAM_DataWidth-1:0] ram_cmdReadData;
    wire                    ram_cmdReadDataValid;

    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),

        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(ram_cmdReadData),
        .cmdReadDataValid(ram_cmdReadDataValid),

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
    
    function [15:0] DataFromAddr;
        input [24:0] addr;
        // DataFromAddr = {addr[24:9]};
        // DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
        DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
        // DataFromAddr = 16'hCAFE;
    endfunction
    
    localparam StateInit        = 0;    // +1
    localparam StateReadMem     = 5;    // +4
    
    reg[3:0] state = 0;
    reg[15:0] lastReadData = 0;
    reg[7:0] memCounter = 0;
    always @(posedge clk) begin
        case (state)
        
        // Initialize the SDRAM
        StateInit: begin
            lastReadData <= 0;
            led <= 0;
            memCounter <= 0;
            ram_cmdAddr <= 0;
            ram_cmdTrigger <= 0;
            ram_cmdWrite <= 0;
            ram_cmdWriteData <= 0;
            
            state <= StateInit+1;
        end
        
        StateInit+1: begin
            if (!ram_cmdTrigger) begin
                ram_cmdTrigger <= 1;
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 1;
                ram_cmdWriteData <= DataFromAddr(0);

            end else if (ram_cmdReady) begin
                ram_cmdAddr <= ram_cmdAddr+1;
                ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1);

                if (ram_cmdAddr == RAM_Size-1) begin
                    ram_cmdTrigger <= 0;
                    state <= StateReadMem;
                end
            end
        end
        
        // Start reading memory
        StateReadMem: begin
            led[0] <= 1;
            ram_cmdAddr <= 0;
            ram_cmdWrite <= 0;
            ram_cmdTrigger <= 1;
            memCounter <= 8'h7F;
            state <= StateReadMem+1;
        end
        
        // Continue reading memory
        StateReadMem+1: begin
            // Handle the read being accepted
            if (ram_cmdReady && memCounter) begin
                ram_cmdAddr <= ram_cmdAddr+1'b1;
                
                // Stop triggering when we've issued all the read commands
                memCounter <= memCounter-1;
                if (memCounter == 1) begin
                    ram_cmdTrigger <= 0;
                end
            end
            
            if (ram_cmdReadDataValid) begin
                led[1] <= 1;
                if (ram_cmdReadData && ram_cmdReadData!=(lastReadData+2'b01)) begin
                    led[3] <= 1;
                end
                lastReadData <= ram_cmdReadData;
            end
        end
        endcase
    end
    
endmodule
