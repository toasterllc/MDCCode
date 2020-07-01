`timescale 1ns/1ps
`include "../AFIFO.v"

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
    wire inq_readTrigger = cmdTrigger;
    reg inq_writeTrigger = 0;
    wire[7:0] inq_readData;
    reg[7:0] inq_writeData = 0;
    wire inq_readOK, inq_writeOK;
    reg[7:0] inq_cmd = 0;
    reg inq_cmdReady = 0;
    AFIFO #(.Width(8), .Size(8)) inq(
        .rclk(clk),
        .r(inq_readTrigger),
        .rd(inq_readData),
        .rok(inq_readOK),
        
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
    AFIFO #(.Width(8), .Size(512)) outq(
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
    assign cmd = inq_cmd;
    assign cmdReady = inq_cmdReady;
    assign msgTrigger = (msgLen && outq_writeTrigger && outq_writeOK);
    
    always @(posedge clk) begin
        // Reset stuff by default
        outq_writeTrigger <= 0;
        inq_cmdReady <= 0;
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
        
        // Read the next command out of `inq`
        end else if (inq_readTrigger && inq_readOK) begin
            inq_cmd <= inq_readData;
            inq_cmdReady <= 1;
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
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do
);
    localparam CmdNop       = 8'h00;
    localparam CmdLEDOff    = 8'h80;
    localparam CmdLEDOn     = 8'h81;
    
    wire clk = clk12mhz;
    
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
    
    always @(posedge clk) begin
        // Set default values
        debug_cmdTrigger <= 0;
        
        // Handle sending response
        if (debug_msgLen) begin
            if (debug_msgTrigger) begin
                debug_msg <= debug_msgLen-1;
                debug_msgLen <= debug_msgLen-1;
            end
        
        // Handle command
        end else if (debug_cmdReady) begin
            case (debug_cmd)
            CmdLEDOff: begin
                led[0] <= 0;
            end
            
            CmdLEDOn: begin
                led[0] <= 1;
            end
            endcase
            
            // Prepare to send response
            debug_msg <= debug_cmd;
            debug_msgLen <= 10;
        
        // Request a new command
        end else begin
            debug_cmdTrigger <= 1;
        end
    end
endmodule
