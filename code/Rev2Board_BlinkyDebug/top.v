`timescale 1ns/1ps
`include "../AFIFO.v"

module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do,
);
    localparam CmdNop       = 8'h00;
    localparam CmdLEDOff    = 8'h80;
    localparam CmdLEDOn     = 8'h81;
    
    wire clk = clk12mhz;
    
    reg inq_readTrigger=0, inq_writeTrigger=0;
    wire[7:0] inq_readData;
    reg[7:0] inq_writeData = 0;
    wire inq_readOK, inq_writeOK;
    reg[7:0] inq_currentCmd = 0;
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
    
    reg[7:0] outMsg[7:0];
    reg[7:0] outMsgLen = 0;
    always @(posedge clk) begin
        // Reset stuff by default
        inq_readTrigger <= 0;
        outq_writeTrigger <= 0;
        inq_currentCmd <= CmdNop;
        
        // Continue shifting out `outMsg`, if there's more data available
        if (outMsgLen) begin
            if (outq_writeTrigger && outq_writeOK) begin
                outMsgLen <= outMsgLen-1;
                // Keep triggering writes if there's more data
                if (outMsgLen > 1) begin
                    outq_writeTrigger <= 1;
                end
            end else begin
                // Keep triggering writes if there's more data
                outq_writeTrigger <= 1;
            end
        
        // Handle `inq_currentCmd` if it exists
        end else if (inq_currentCmd != CmdNop) begin
            // Handle inq_currentCmd
            case (inq_currentCmd)
            CmdLEDOff: begin
                led[0] <= 0;
            end
            
            CmdLEDOn: begin
                led[0] <= 1;
            end
            
            // default: begin
            //     led[0] <= 1;
            // end
            endcase
            
            // Queue response
            outMsg[1] <= 1;
            outMsg[0] <= inq_currentCmd;
            outMsgLen <= 2;
        
        // Read the next command out of `inq`
        end else if (inq_readTrigger && inq_readOK) begin
            inq_currentCmd <= inq_readData;
        
        // Otherwise trigger a new read
        end else begin
            inq_readTrigger <= 1;
        end
    end
    
    
    
    
    
    reg outq_readTrigger=0, outq_writeTrigger=0;
    wire[7:0] outq_readData;
    wire[7:0] outq_writeData = outMsg[(outMsgLen ? outMsgLen-1 : 0)];
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
    
    reg[7:0] inCmd = 0;
    wire inCmdReady = inCmd[7];
    reg[8:0] outq_currentData = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = outq_currentData[8];
    always @(posedge debug_clk) begin
        if (debug_cs) begin
            // Reset stuff by default
            inq_writeTrigger <= 0;
            outq_readTrigger <= 0;
            
            if (inq_writeTrigger && !inq_writeOK) begin
                // TODO: handle dropped commands
            end
            
            // ## Incoming data handling (inq)
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
            
            // ## Outgoing data handling (outq)
            // Continue shifting out the current data, if there's still data remaining
            if (outq_currentData[6:0]) begin
                outq_currentData <= outq_currentData<<1;
                
                // Trigger a read on the correct clock cycle
                if (outq_currentData[6:0] == 8'b01000000) begin
                    outq_readTrigger <= 1;
                end
            
            // Otherwise load the next byte, if there's one available
            end else if (outq_readTrigger && outq_readOK) begin
                outq_currentData <= {outq_readData, 1'b1}; // Add sentinel to the end
            
            end else if (!outq_currentData) begin
                outq_currentData <= {8'b1, 1'b0}; // Add sentinel to the end
            
            // Otherwise shift out zeroes
            end else begin
                outq_currentData <= {8'b0, 1'b1}; // Add sentinel to the end
            end
        end
    end
    
    // assign led[3:0] = 4'b1111;
    
endmodule
