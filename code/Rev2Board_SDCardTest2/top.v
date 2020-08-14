`include "../ClockGen.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps






module CRC7(
    input wire clk,
    input wire en,
    input din,
    output wire[6:0] dout
);
    reg[6:0] d = 0;
    wire dx = din ^ d[6];
    wire[6:0] dnext = { d[5], d[4], d[3], d[2] ^ dx, d[1], d[0], dx };
    assign dout = dnext;
    always @(posedge clk)
        d <= (!en ? 0 : dnext);
endmodule







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







// SyncPulse
//   Transmits a single-clock pulse across clock domains.
//   Pulses can be dropped if they occur more rapidly than they can be acknowledged.
module SyncPulse(
    input wire in_clk,
    input wire in_pulse,
    
    input wire out_clk,
    output wire out_pulse
);
    reg in_req = 0;
    wire in_ack;
    wire idle = !in_req && !in_ack;
    always @(posedge in_clk) begin
    	if (idle && in_pulse)   in_req <= 1;
    	else if (in_ack)        in_req <= 0;
    end
    
    reg pipe1 = 0;
    always @(posedge out_clk)
        { out_req, pipe1 } <= { pipe1, in_req };
    
    reg pipe2 = 0;
    always @(posedge in_clk)
        { in_ack, pipe2 } <= { pipe2, out_req };
    
    reg out_lastReq = 0;
    always @(posedge out_clk)
        out_lastReq <= out_req;
    
    assign out_pulse = out_lastReq && !out_req; // Out pulse occurs upon negative edge of out_req.
endmodule







module SDCardController #(
    parameter ClkFreq = 12000000,       // `clk` frequency
    parameter SDClkMaxFreq = 400000     // max `sd_clk` frequency
)(
    input wire          clk12mhz,
    
    // Command port
    input wire          cmd_clk,
    input wire          cmd_trigger,
    input wire[37:0]    cmd_cmd,
    output wire[135:0]  cmd_resp,
    output wire         cmd_done,
    
    // SDIO port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    // Internal clock (96 MHz)
    localparam IntClkFreq = 96000000;
    wire int_clk;
    ClockGen #(
        .FREQ(IntClkFreq),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(int_clk));
    
    // `cmd_trigger` synchronizer into internal (int_) clock domain
    wire int_trigger;
    SyncPulse sp(
        .in_clk(cmd_clk),
        .in_pulse(cmd_trigger),
        .out_clk(int_clk),
        .out_pulse(int_trigger)
    );
    
    always @(posedge int_clk) begin
        cmdOutReg <= cmdOutReg<<1;
        counter <= counter-1;
        resp <= (resp<<1)|cmdIn;
        
        case (state)
        StateIdle: begin
            cmd_done <= 0; // Reset from last state
            
            if (cmd_trigger) begin
                cmdOutReg <= {2'b01, cmd_cmd};
                cmdOutActive <= 1;
                counter <= 40;
                state <= StateCmd;
            end
        end
        
        StateCmd: begin
            if (counter == 1) begin
                // If this was the last bit, send the CRC, followed by the '1' end bit
                cmdOutReg <= {cmdCRC, 1'b1, 32'b0};
                counter <= 8;
                state <= StateCmd+1;
            end
        end
        
        StateCmd+1: begin
            if (counter == 1) begin
                // If this was the last bit, wrap up
                cmdOutActive <= 0;
                state <= StateResp;
            end
        end
        
        StateResp: begin
            // Wait for the response to start
            if (!cmdIn) begin
                counter <= 135;
                state <= StateResp+1;
            end
        end
        
        StateResp+1: begin
            if (counter == 1) begin
                // If this was the last bit, wrap up
                cmd_done <= 1;
                state <= StateIdle;
            end
        end
        endcase
    end
    
    // function [63:0] DivCeil;
    //     input [63:0] n;
    //     input [63:0] d;
    //     begin
    //         DivCeil = (n+d-1)/d;
    //     end
    // endfunction
    //
    // localparam SDClkDividerWidth = $clog2(DivCeil(ClkFreq, SDClkMaxFreq));
    // reg[SDClkDividerWidth-1:0] sdClkDivider = 0;
    // assign sd_clk = sdClkDivider[SDClkDividerWidth-1];
    //
    // always @(posedge clk) begin
    //     sdClkDivider <= sdClkDivider+1;
    // end
    // assign sd_clk = clk;
    
    localparam CmdOutRegWidth = 40;
    reg[CmdOutRegWidth-1:0] cmdOutReg = 0;
    wire cmdOut = cmdOutReg[CmdOutRegWidth-1];
    reg cmdOutActive = 0;
    wire cmdIn;
    reg[7:0] counter = 0;
    
    reg[135:0] resp = 0;
    assign cmd_resp = resp;
    
    wire[6:0] cmdCRC;
    CRC7 crc7(
        .clk(intClk),
        .en(cmdOutActive),
        .din(cmdOut),
        .dout(cmdCRC)
    );
    
    SB_IO #(
        .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
        // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
        .NEG_TRIGGER(1'b1)
    ) sbio (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_ENABLE(cmdOutActive),
        .OUTPUT_CLK(intClk),
        .D_OUT_0(cmdOut),
        .D_IN_0(cmdIn)
    );
    
    reg[3:0] dataOut = 0;
    reg dataOutActive = 0;
    wire[3:0] dataIn;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
            // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
            .NEG_TRIGGER(1'b1)
        ) sbio (
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_ENABLE(dataOutActive),
            .OUTPUT_CLK(intClk),
            .D_OUT_0(dataOut[i]),
            .D_IN_0(dataIn[i])
        );
    end
    
    reg[5:0] state = 0;
    localparam StateIdle    = 0;   // +0
    localparam StateCmd     = 1;   // +1
    localparam StateResp    = 3;   // +1
    
    always @(posedge intClk) begin
    end
    
endmodule








module Top(
    input wire          clk12mhz,
    output reg[3:0]     led = 0 /* synthesis syn_keep=1 */,
    
    output wire         sd_clk  /* synthesis syn_keep=1 */,
    
`ifdef SIM
    inout tri1          sd_cmd,
`else
    inout wire          sd_cmd  /* synthesis syn_keep=1 */,
`endif
    
    inout wire[3:0]     sd_dat  /* synthesis syn_keep=1 */
);
    // // ====================
    // // Clock PLL (100.5 MHz)
    // // ====================
    // localparam ClkFreq = 100500000;
    // wire pllClk;
    // ClockGen #(
    //     .FREQ(ClkFreq),
    //     .DIVR(0),
    //     .DIVF(66),
    //     .DIVQ(3),
    //     .FILTER_RANGE(1)
    // ) cg(.clk12mhz(clk12mhz), .clk(pllClk));
    
    // // ====================
    // // Clock PLL (91.5 MHz)
    // // ====================
    // localparam ClkFreq = 91500000;
    // wire pllClk;
    // ClockGen #(
    //     .FREQ(ClkFreq),
    //     .DIVR(0),
    //     .DIVF(60),
    //     .DIVQ(3),
    //     .FILTER_RANGE(1)
    // ) cg(.clk12mhz(clk12mhz), .clk(pllClk));
    
    // ====================
    // Clock PLL (81 MHz)
    // ====================
    localparam ClkFreq = 81000000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(53),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    
    // ====================
    // SD Card Controller
    // ====================
    reg         sd_cmd_trigger = 0;
    reg[37:0]   sd_cmd_cmd = 0;
    wire[135:0] sd_cmd_resp;
    wire        sd_cmd_done;
    SDCardController #(
        .ClkFreq(ClkFreq),
        .SDClkMaxFreq(400000)
    ) sdctrl(
        .clk(clk),
        
        .cmd_trigger(sd_cmd_trigger),
        .cmd_cmd(sd_cmd_cmd),
        .cmd_resp(sd_cmd_resp),
        .cmd_done(sd_cmd_done),
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    
    
    // initial begin
    //     #1000000;
    //     $finish;
    // end
    
    initial begin
        #10000;
        wait(!sd_clk);
        
        sd_cmd_trigger = 1;
        sd_cmd_cmd = {6'b000000, 32'b0};
        wait(sd_clk);
        #100;
        sd_cmd_trigger = 0;
        
        wait(sd_clk & sd_cmd_done);
        
        $display("Got response: %b [preamble: %b, index: %0d, arg: %x, crc: %b, stop: %b]",
            sd_cmd_resp,
            sd_cmd_resp[135:134],   // preamble
            sd_cmd_resp[133:128],   // index
            sd_cmd_resp[127:96],    // arg
            sd_cmd_resp[95:89],     // crc
            sd_cmd_resp[88],       // stop bit
        );
        
        #10000;
        $finish;
    end
    
    // SD card emulator
    // Handle receiving commands and providing responses
    reg[47:0] sim_cmdIn = 0;
    reg[47:0] sim_respOut = 0;
    reg sim_cmdOut = 1'bz;
    assign sd_cmd = sim_cmdOut;
    
    initial begin
        forever begin
            wait(sd_clk);
            
            if (!sd_cmd) begin
                // Receive incoming command
                reg[7:0] i;
                for (i=0; i<48; i++) begin
                    sim_cmdIn = (sim_cmdIn<<1)|sd_cmd;
                    wait(!sd_clk);
                    wait(sd_clk);
                end
                
                $display("Received command: %b [preamble: %b, index: %0d, arg: %x, crc: %b, stop: %b]",
                    sim_cmdIn,
                    sim_cmdIn[47:46],   // preamble
                    sim_cmdIn[45:40],   // index
                    sim_cmdIn[39:8],    // arg
                    sim_cmdIn[7:1],     // crc
                    sim_cmdIn[0],       // stop bit
                );
                
                // Issue response
                sim_respOut = {47'b0, 1'b1};
                $display("Sending response: %b", sim_respOut);
                for (i=0; i<48; i++) begin
                    wait(!sd_clk);
                    sim_cmdOut = sim_respOut[47];
                    sim_respOut = sim_respOut<<1;
                    wait(sd_clk);
                end
                wait(!sd_clk);
                sim_cmdOut = 1'bz;
                
                $display("  -> Sent");
            end
            
            wait(!sd_clk);
        end
    end
    
`endif
    
endmodule
