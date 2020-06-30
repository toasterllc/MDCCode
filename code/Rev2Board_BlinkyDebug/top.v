`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0,
    
    input wire          debug_clk,
    input wire          debug_cs,
    input wire          debug_di,
    output wire         debug_do,
);
    localparam CmdNop               = 8'h00;
    localparam CmdLEDOff            = 8'h80;
    localparam CmdLEDOn             = 8'h81;
    
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
    
    reg[7:0] cmd = 0;
    wire cmdReady = cmd[7];
    always @(posedge debug_clk) begin
        if (debug_cs) begin
            // Handle command
            if (cmdReady) begin
                
                case (cmd)
                CmdNop: begin
                    
                end
                
                CmdLEDOff: begin
                    led[0] <= 0;
                end
                
                CmdLEDOn: begin
                    led[0] <= 1;
                end
                endcase
                
                // Start next command
                cmd <= debug_di;
            
            // Keep shifting in command
            end else begin
                cmd <= (cmd<<1)|debug_di;
            end
        end
    end
    
    // assign led[3:0] = 4'b1111;
    
endmodule
