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
    
    // reg tmp = 0;
    // assign led[0] = tmp;
    
    // reg[23:0] counter = 0;
    // assign led[3:0] = counter[11: 8];
    // assign led[3:0] = counter[ 7: 4];
    // assign led[3:0] = counter[ 3: 0];
    
    // assign led[3:0] = {4{counter == 35}};
    // assign led[3:0] = {4{counter == 0}};
    
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
        .w(inq_writeTrigger),
        .wd(inq_writeData),
        .wok(inq_writeOK)
    );
    
    always @(posedge clk) begin
        // Reset inq_readTrigger by default
        inq_readTrigger <= 0;
        // Reset currentCmd by default
        inq_currentCmd <= CmdNop;
        
        if (inq_readOK) begin
            inq_currentCmd <= inq_readData;
            inq_readTrigger <= 1;
        end else begin
            inq_currentCmd <= CmdNop;
        end
        
        // Handle inq_currentCmd
        case (inq_currentCmd)
        CmdNop: begin
        end
        
        CmdLEDOff: begin
            led[0] <= 0;
        end
        
        CmdLEDOn: begin
            led[0] <= 1;
        end
        endcase
    end
    
    
    
    
    
    reg outq_readTrigger=0, outq_writeTrigger=0;
    wire[7:0] outq_readData;
    reg[7:0] outq_writeData = 0;
    wire outq_readOK, outq_writeOK;
    reg[8:0] outq_currentData = 0; // Low bit is the end-of-data sentinel, and isn't transmitted
    assign debug_do = outq_currentData[8];
    
    AFIFO #(.Width(8), .Size(512)) outq(
        .rclk(debug_clk),
        .r(outq_readTrigger),
        .rd(outq_readData),
        .rok(outq_readOK),
        
        .wclk(clk),
        .w(outq_writeTrigger),
        .wd(outq_writeData),
        .wok(outq_writeOK)
    );
    
    reg[7:0] debug_cmd = 0;
    wire debug_cmdReady = debug_cmd[7];
    always @(posedge debug_clk) begin
        // Reset outq_readTrigger/inq_writeTrigger by default
        inq_writeTrigger <= 0;
        outq_readTrigger <= 0;
        
        if (debug_cs) begin
            // ## Incoming command handling (inq)
            // Continnue shifting in command
            if (!debug_cmdReady) begin
                debug_cmd <= (debug_cmd<<1)|debug_di;
            
            // Enqueue the command into inq
            end else begin
                if (inq_writeOK) begin
                    inq_writeData <= debug_cmd;
                    inq_writeTrigger <= 1;
                end else begin
                    // TODO: handle dropped command
                end
                
                // Start shifting the next command
                debug_cmd <= debug_di;
            end
            
            // ## Outgoing data handling (outq)
            // Continue shifting out the current data, if there's still data remaining
            if (outq_currentData[6:0]) begin
                outq_currentData <= outq_currentData<<1;
            
            // Otherwise load the next byte, if there's one available
            end else if (outq_readOK) begin
                outq_currentData <= {outq_readData, 1'b1}; // Add sentinel to the end
                outq_readTrigger <= 1;
            
            // Otherwise shift out zeroes
            end else begin
                outq_currentData <= {8'b0, 1'b1}; // Add sentinel to the end
            end
        end
    end
    
    // assign led[3:0] = 4'b1111;
    
endmodule
