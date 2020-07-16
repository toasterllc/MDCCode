`timescale 1ns/1ps


// Sync:
// Synchronizes an asynchronous signal into a clock domain
module Sync(
    input wire in,
    
    input wire out_clk,
    output reg out = 0
);
    reg pipe = 0;
    always @(posedge out_clk)
        { out, pipe } <= { pipe, in };
endmodule







// SyncPulse:
// Transmits a single-clock pulse across clock domains
// Pulses can be dropped if they occur more rapidly than they can be acknowledged.
module SyncPulse(
    input wire in_clk,
    input wire in,
    
    input wire out_clk,
    output wire out
);
    reg in_req = 0;
    wire in_ack;
    wire idle = !in_req && !in_ack;
    always @(posedge in_clk) begin
    	if (idle && in)     in_req <= 1;
    	else if (in_ack)    in_req <= 0;
    end
    
    wire out_req;
    Sync syncReq(.in(in_req), .out_clk(out_clk), .out(out_req));
    Sync syncAck(.in(out_req), .out_clk(in_clk), .out(in_ack));
    
    reg out_lastReq = 0;
    assign out = out_lastReq && !out_req; // Out pulse occurs upon negative edge of out_req.
    always @(posedge out_clk) out_lastReq <= out_req;
endmodule










module Top();
    reg clkA = 0;
    reg clkB = 0;
    
    reg pulseA = 0;
    wire pulseB;
    SyncPulse syncPulse(.in_clk(clkA), .in(pulseA), .out_clk(clkB), .out(pulseB));
    
    reg[3:0] delay = 0;
    reg didPulse1 = 0;
    reg didPulse2 = 0;
    always @(posedge clkA) begin
        if (!(&delay)) delay <= delay+1;
        else if (!didPulse1) begin
            if (!pulseA) pulseA <= 1;
            else begin
                pulseA <= 0;
                didPulse1 <= 1;
                delay <= 0;
            end
        end
        
        else if (!didPulse2) begin
            if (!pulseA) pulseA <= 1;
            else begin
                pulseA <= 0;
                didPulse2 <= 1;
            end
        end
        
    end
    
    always @(posedge clkB) begin
        if (pulseB) begin
            $display("GOT PULSE");
        end
    end
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        forever begin
            clkA = 0;
            #10;
            clkA = 1;
            #10;
        end
    end
    
    initial begin
        forever begin
            clkB = 0;
            #33;
            clkB = 1;
            #33;
        end
    end
endmodule
