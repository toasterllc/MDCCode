`include "../ClockGen.v"
`include "../MsgChannel.v"
`include "../SDCardController.v"

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
