`timescale 1ns/1ps
`include "../ClockGen.v"
`include "../AFIFO.v"
// `include "../SDRAMController.v"

module Debug(
    input wire          clk,
    
    output wire[7:0]    cmd,
    output wire         cmdReady,
    input wire          cmdTrigger,
    
    input wire[7:0]     msg,
    input wire[7:0]     msgLen,
    output wire         msgTrigger,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
);
    // ====================
    // In queue `inq`
    // ====================
    reg inq_writeTrigger = 0;
    reg[7:0] inq_writeData = 0;
    wire inq_writeOK;
    AFIFO #(.Width(8), .Size(8)) inq(
        .rclk(clk),
        .r(cmdTrigger),
        .rd(cmd),
        .rok(cmdReady),
        
        .wclk(debug_clk),
        .w(debug_cs && inq_writeTrigger),
        .wd(inq_writeData),
        .wok(inq_writeOK)
    );
    
    // ====================
    // Out queue `outq`
    // ====================
    reg outq_readTrigger=0, outq_writeTrigger=0;
    wire[7:0] outq_readData;
    reg[7:0] outq_writeData = 0;
    wire outq_readOK, outq_writeOK;
    AFIFO #(.Width(8), .Size(8)) outq(
        .rclk(debug_clk),
        .r(debug_cs && outq_readTrigger),
        .rd(outq_readData),
        .rok(outq_readOK),
        
        .wclk(clk),
        .w(outq_writeTrigger),
        .wd(outq_writeData),
        .wok(outq_writeOK)
    );
    
    // ====================
    // Command+response handling
    // ====================
    reg msgLenSent = 0;
    assign msgTrigger = (msgLen && outq_writeTrigger && outq_writeOK);
    
    always @(posedge clk) begin
        // Reset stuff by default
        outq_writeTrigger <= 0;
        // msgTrigger <= 0;
        msgLenSent <= 0;
        
        // Continue shifting out `msg`, if there's more data available
        if (msgLen) begin
            // Send the message length first
            if (!msgLenSent) begin
                outq_writeData <= msgLen;
                outq_writeTrigger <= 1;
                
                // Once the message length is sent, start sending the message
                if (outq_writeTrigger && outq_writeOK) begin
                    msgLenSent <= 1;
                    outq_writeData <= msg;
                    outq_writeTrigger <= 1;
                end
            
            // Continue sending the message
            end else begin
                // Keep msgLenSent=1 until the end of the message
                msgLenSent <= 1;
                outq_writeData <= msg;
                outq_writeTrigger <= 1;
            end
        end
    end
    
    // ====================
    // Data relay/shifting (debug_di->inq, outq->debug_do)
    // ====================
    reg[7:0] inCmd = 0;
    wire inCmdReady = inCmd[7];
    reg[8:0] outMsgShiftReg = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = outMsgShiftReg[8];
    always @(posedge debug_clk) begin
        if (debug_cs) begin
            // Reset stuff by default
            inq_writeTrigger <= 0;
            outq_readTrigger <= 0;
            
            if (inq_writeTrigger && !inq_writeOK) begin
                // TODO: handle dropped commands
            end
            
            // ## Incoming command relay: debug_di -> inq
            // Continue shifting in command
            if (!inCmdReady) begin
                inCmd <= (inCmd<<1)|debug_di;
            
            // Enqueue the command into `inq`
            end else begin
                inq_writeTrigger <= 1;
                inq_writeData <= inCmd;
                
                // Start shifting the next command
                inCmd <= debug_di;
            end
            
            // ## Outgoing message relay: outq -> debug_do
            // Continue shifting out the current data, if there's still data remaining
            if (outMsgShiftReg[6:0]) begin
                outMsgShiftReg <= outMsgShiftReg<<1;
                
                // Trigger a read on the correct clock cycle
                if (outMsgShiftReg[6:0] == 8'b01000000) begin
                    outq_readTrigger <= 1;
                end
            
            // Otherwise load the next byte, if there's one available
            end else if (outq_readTrigger && outq_readOK) begin
                outMsgShiftReg <= {outq_readData, 1'b1}; // Add sentinel to the end
            
            end else begin
                // outMsgShiftReg initialization must be as if it was originally
                // initialized to 1, so after the first clock cycle it should be 1<<1.
                if (!outMsgShiftReg) outMsgShiftReg <= 1<<1;
                else outMsgShiftReg <= 1;
            end
        end
    end
endmodule





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
    inout wire[15:0]    ram_dq,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
);
    // ====================
    // Clock PLL (90 MHz)
    // ====================
    localparam ClockFrequency = 90000000;
    wire clk;
    ClockGen #(
        .FREQ(ClockFrequency),
		.DIVR(0),
		.DIVF(59),
		.DIVQ(3),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    
    
    
    
    
    // ====================
    // SDRAM controller
    // ====================
    localparam RAM_Size = 'h2000000;
    localparam RAM_AddrWidth = 25;
    localparam RAM_DataWidth = 16;

    // RAM controller
    wire                    ram_cmdReady;
    reg                     ram_cmdTrigger = 0;
    reg[RAM_AddrWidth-1:0]  ram_cmdAddr = 0;
    reg                     ram_cmdWrite = 0;
    reg[RAM_DataWidth-1:0]  ram_cmdWriteData = 0;

    SDRAMController #(
        .ClockFrequency(ClockFrequency)
    ) sdramController(
        .clk(clk),

        .cmdReady(ram_cmdReady),
        .cmdTrigger(ram_cmdTrigger),
        .cmdAddr(ram_cmdAddr),
        .cmdWrite(ram_cmdWrite),
        .cmdWriteData(ram_cmdWriteData),
        .cmdReadData(),
        .cmdReadDataValid(),

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
    
    
    
    
    
    
    
    
    
    
    
    
    // ====================
    // Debug I/O
    // ====================
    localparam CmdNop       = 8'h00;
    localparam CmdLEDOff    = 8'h80;
    localparam CmdLEDOn     = 8'h81;
    localparam CmdReadMem   = 8'h82;
    
    wire[7:0] debug_cmd;
    wire debug_cmdReady;
    reg debug_cmdTrigger = 0;
    
    reg[7:0] debug_msg = 0;
    reg[7:0] debug_msgLen = 0;
    wire debug_msgTrigger;
    
    reg[7:0] cmd = 0;
    reg cmdReady = 0;
    
    Debug debug(
        .clk(clk),
        
        .cmd(debug_cmd),
        .cmdReady(debug_cmdReady),
        .cmdTrigger(debug_cmdTrigger),
        
        .msg(debug_msg),
        .msgLen(debug_msgLen),
        .msgTrigger(debug_msgTrigger),
        
        .debug_clk(debug_clk),
        .debug_cs(debug_cs),
        .debug_di(debug_di),
        .debug_do(debug_do)
    );
    
    
    
    
    
    
    
    
    
    
    
    
    // ====================
    // Main
    // ====================
    function [15:0] DataFromAddr;
        input [24:0] addr;
        DataFromAddr = {7'h55, addr[24:16]} ^ ~(addr[15:0]);
        // DataFromAddr = addr[15:0];
        // DataFromAddr = 16'hFFFF;
        // DataFromAddr = 16'h0000;
        // DataFromAddr = 16'h7832;
    endfunction
    
    reg init = 0;
    reg readMem = 0;
    reg[7:0] memBuf[511:0];
    reg[8:0] memBufRead = 0;
    reg[8:0] memBufWrite = 0;
    
    reg[7:0] cmd = CmdNop;
    always @(posedge clk) begin
        // Set default values
        ram_cmdTrigger <= 0;
        debug_cmdTrigger <= 0;
        cmd <= CmdNop;
        
        // Initialize the SDRAM
        if (!init) begin
            if (!ram_cmdTrigger) begin
                ram_cmdTrigger <= 1;
                ram_cmdAddr <= 0;
                ram_cmdWrite <= 1;
                ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1);
            
            end else if (ram_cmdTrigger && ram_cmdReady) begin
                if (ram_cmdAddr < RAM_Size-1) begin
                    ram_cmdTrigger <= 1;
                    ram_cmdAddr <= ram_cmdAddr+1;
                    ram_cmdWrite <= 1;
                    ram_cmdWriteData <= DataFromAddr(ram_cmdAddr+1);
                end else begin
                    init <= 1;
                end
            end
        
        // Handle commands
        end else begin
            // if (readMem) begin
            //
            // end
            
            // Handle sending messages
            if (debug_msgLen) begin
                if (debug_msgTrigger) begin
                    debug_msg <= debug_msgLen-1;
                    debug_msgLen <= 0;
                end
            
            end else begin
                // Handle current command
                case (cmd)
                CmdLEDOff: begin
                    led[0] <= 0;
                    debug_msg <= cmd;
                    debug_msgLen <= 1;
                end
                
                CmdLEDOn: begin
                    led[0] <= 1;
                    debug_msg <= cmd;
                    debug_msgLen <= 1;
                end
                
                CmdReadMem: begin
                    readMem <= 1;
                end
                endcase
                
                // Accept commands while we're not sending responses
                debug_cmdTrigger <= 1;
                if (debug_cmdTrigger && debug_cmdReady) begin
                    cmd <= debug_cmd;
                end
            end
        end
    end
endmodule
