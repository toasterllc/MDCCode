`include "../ClockGen.v"
`include "../MsgChannel.v"

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




module SDCardController(
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
    // ====================
    // Internal clock (96 MHz)
    // ====================
    localparam IntClkFreq = 96000000;
    wire int_clk;
    ClockGen #(
        .FREQ(IntClkFreq),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(int_clk));
    
    // ====================
    // Synchronization
    //   {cmd_trigger, cmd_cmd} -> {int_trigger, int_cmd}
    // ====================
    wire int_trigger;
    wire[37:0] int_cmd;
    MsgChannel #(
        .MsgLen(38)
    ) cmdChannel(
        .in_clk(cmd_clk),
        .in_trigger(cmd_trigger),
        .in_msg(cmd_cmd),
        .out_clk(int_clk),
        .out_trigger(int_trigger),
        .out_msg(int_cmd)
    );
    
    // ====================
    // Synchronization
    //   {int_done, int_resp} -> {cmd_done, cmd_resp}
    // ====================
    reg int_done = 0;
    reg[135:0] int_resp = 0;
    MsgChannel #(
        .MsgLen(136)
    ) respChannel(
        .in_clk(int_clk),
        .in_trigger(int_done),
        .in_msg(int_resp),
        .out_clk(cmd_clk),
        .out_trigger(cmd_done),
        .out_msg(cmd_resp)
    );
    
    reg[39:0] int_cmdOutReg = 0;
    wire int_cmdOut = int_cmdOutReg[39];
    reg int_cmdOutActive = 0;
    wire int_cmdIn;
    reg[7:0] int_counter = 0;
    
    // ====================
    // `sd_cmd` IO Pin
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
        // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
        .NEG_TRIGGER(1'b1)
    ) sbio (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_CLK(int_clk),
        .OUTPUT_ENABLE(int_cmdOutActive),
        .D_OUT_0(int_cmdOut),
        .D_IN_0(int_cmdIn)
    );
    
    // ====================
    // CRC
    // ====================
    wire[6:0] int_cmdCRC;
    CRC7 crc7(
        .clk(int_clk),
        .en(int_cmdOutActive),
        .din(int_cmdOut),
        .dout(int_cmdCRC)
    );
    
    // ====================
    // State Machine
    // ====================
    localparam StateIdle    = 0;   // +0
    localparam StateCmd     = 1;   // +1
    localparam StateResp    = 3;   // +1
    reg[5:0] int_state = 0;
    always @(posedge int_clk) begin
        int_cmdOutReg <= int_cmdOutReg<<1;
        int_counter <= int_counter-1;
        int_resp <= (int_resp<<1)|int_cmdIn;
        
        case (int_state)
        StateIdle: begin
            int_done <= 0; // Reset from previous state
            
            if (int_trigger) begin
                int_cmdOutReg <= {2'b01, int_cmd};
                int_cmdOutActive <= 1;
                int_counter <= 40;
                int_state <= StateCmd;
            end
        end
        
        StateCmd: begin
            if (int_counter == 1) begin
                // If this was the last bit, send the CRC, followed by the '1' end bit
                int_cmdOutReg <= {int_cmdCRC, 1'b1, 32'b0};
                int_counter <= 8;
                int_state <= StateCmd+1;
            end
        end
        
        StateCmd+1: begin
            if (int_counter == 1) begin
                // If this was the last bit, wrap up
                int_cmdOutActive <= 0;
                int_state <= StateResp;
            end
        end
        
        StateResp: begin
            // Wait for the response to start
            if (!int_cmdIn) begin
                int_counter <= 135;
                int_state <= StateResp+1;
            end
        end
        
        StateResp+1: begin
            if (int_counter == 1) begin
                // If this was the last bit, wrap up
                int_done <= 1;
                int_state <= StateIdle;
            end
        end
        endcase
    end
    
    assign sd_clk = int_clk;
    
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
    
    // reg[3:0] dataOut = 0;
    // reg dataOutActive = 0;
    // wire[3:0] dataIn;
    // genvar i;
    // for (i=0; i<4; i=i+1) begin
    //     SB_IO #(
    //         .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
    //         // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
    //         .NEG_TRIGGER(1'b1)
    //     ) sbio (
    //         .PACKAGE_PIN(sd_dat[i]),
    //         .OUTPUT_CLK(intClk),
    //         .OUTPUT_ENABLE(dataOutActive),
    //         .D_OUT_0(dataOut[i]),
    //         .D_IN_0(dataIn[i])
    //     );
    // end
    
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
    SDCardController sdctrl(
        .clk12mhz(clk12mhz),
        
        .cmd_clk(clk),
        .cmd_trigger(sd_cmd_trigger),
        .cmd_cmd(sd_cmd_cmd),
        .cmd_resp(sd_cmd_resp),
        .cmd_done(sd_cmd_done),
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    reg state = 0;
    always @(posedge clk) begin
        case (state)
        0: begin
            sd_cmd_trigger <= 1;
            sd_cmd_cmd <= {6'b000000, 32'b0};
            state <= 1;
            
            `ifdef SIM
                $display("Sending SD command: %b", sd_cmd_cmd);
            `endif
        end
        
        1: begin
            sd_cmd_trigger <= 0;
            if (sd_cmd_done) begin
                `ifdef SIM
                    $display("Received response: %b [preamble: %b, index: %0d, arg: %x, crc: %b, stop: %b]",
                        sd_cmd_resp,
                        sd_cmd_resp[135:134],   // preamble
                        sd_cmd_resp[133:128],   // index
                        sd_cmd_resp[127:96],    // arg
                        sd_cmd_resp[95:89],     // crc
                        sd_cmd_resp[88],        // stop bit
                    );
                `endif
                
                state <= 0;
            end
        end
        endcase
    end
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    
    
    // initial begin
    //     #1000000;
    //     $finish;
    // end
    
    // ====================
    // SD host emulator
    //   Send commands, receive responses
    // ====================
    // initial begin
    //     forever begin
    //         wait(!clk);
    //         sd_cmd_trigger = 1;
    //         sd_cmd_cmd = {6'b000000, 32'b0};
    //         wait(clk);
    //         #100;
    //         sd_cmd_trigger = 0;
    //
    //         wait(clk & sd_cmd_done);
    //
    //         $display("Got response: %b [preamble: %b, index: %0d, arg: %x, crc: %b, stop: %b]",
    //             sd_cmd_resp,
    //             sd_cmd_resp[135:134],   // preamble
    //             sd_cmd_resp[133:128],   // index
    //             sd_cmd_resp[127:96],    // arg
    //             sd_cmd_resp[95:89],     // crc
    //             sd_cmd_resp[88],       // stop bit
    //         );
    //     end
    //     $finish;
    // end
    
    // ====================
    // SD card emulator
    //   Receive commands, issue responses
    // ====================
    reg[47:0] sim_cmdIn = 0;
    reg[47:0] sim_respOut = 0;
    reg sim_cmdOut = 1'bz;
    assign sd_cmd = sim_cmdOut;
    
    initial begin
        forever begin
            wait(sd_clk);
            
            if (!sd_cmd) begin
                // Receive command
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
            end
            
            wait(!sd_clk);
        end
    end
    
`endif
    
endmodule
