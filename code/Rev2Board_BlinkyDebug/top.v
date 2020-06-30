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
    
    assign debug_do = 0;
    
    reg cmdq_readTrigger=0, cmdq_writeTrigger=0;
    wire[7:0] cmdq_readData;
    reg[7:0] cmdq_writeData = 0;
    wire cmdq_readOK, cmdq_writeOK;
    reg[7:0] cmdq_currentCmd = 0;
    
    AFIFO #(.Width(8), .Size(8)) cmdqfifo(
        .rclk(clk),
        .r(cmdq_readTrigger),
        .rd(cmdq_readData),
        .rok(cmdq_readOK),
        
        .wclk(debug_clk),
        .w(cmdq_writeTrigger),
        .wd(cmdq_writeData),
        .wok(cmdq_writeOK)
    );
    
    always @(posedge clk) begin
        // Reset cmdq_readTrigger by default
        cmdq_readTrigger <= 0;
        // Reset currentCmd by default
        cmdq_currentCmd <= CmdNop;
        
        if (cmdq_readOK) begin
            cmdq_currentCmd <= cmdq_readData;
            cmdq_readTrigger <= 1;
        end else begin
            cmdq_currentCmd <= CmdNop;
        end
        
        // Handle cmdq_currentCmd
        case (cmdq_currentCmd)
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
    
    // wire outbuf_readTrigger, outbuf_writeTrigger;
    // wire[7:0] outbuf_readData;
    // reg[7:0] outbuf_writeData = 0;
    // wire outbuf_readOK, outbuf_writeOK;
    // AFIFO #(.Width(8), .Size(512)) outbuf(
    //     .rclk(debug_clk),
    //     .r(outbuf_readTrigger),
    //     .rd(outbuf_readData),
    //     .rok(outbuf_readOK),
    //
    //     .wclk(clk),
    //     .w(outbuf_writeTrigger),
    //     .wd(outbuf_writeData),
    //     .wok(outbuf_writeOK)
    // );
    
    reg[7:0] debug_cmd = 0;
    wire debug_cmdReady = debug_cmd[7];
    always @(posedge debug_clk) begin
        // Reset cmdq_writeTrigger by default
        cmdq_writeTrigger <= 0;
        
        if (debug_cs) begin
            // Keep shifting in command
            if (!debug_cmdReady) begin
                debug_cmd <= (debug_cmd<<1)|debug_di;
            
            // Enqueue the command into cmdqfifo
            end else begin
                if (cmdq_writeOK) begin
                    cmdq_writeData <= debug_cmd;
                    cmdq_writeTrigger <= 1;
                end else begin
                    // TODO: handle dropped command
                end
                
                // Start shifting the next command
                debug_cmd <= debug_di;
            end
        end
    end
    
    // assign led[3:0] = 4'b1111;
    
endmodule
