`include "../ClockGen.v"
`include "../SDCardController.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps










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
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    // reg state = 0;
    // always @(posedge clk) begin
    //     case (state)
    //     0: begin
    //         sd_cmd_trigger <= 1;
    //         sd_cmd_cmd <= {6'b000000, 32'b0};
    //         state <= 1;
    //
    //         `ifdef SIM
    //             $display("Sending SD command: %b", sd_cmd_cmd);
    //         `endif
    //     end
    //
    //     1: begin
    //         sd_cmd_trigger <= 0;
    //         if (sd_cmd_done) begin
    //             `ifdef SIM
    //                 $display("Received response: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, stop: %b ]",
    //                     sd_cmd_resp,
    //                     sd_cmd_resp[135:134],   // preamble
    //                     sd_cmd_resp[133:128],   // index
    //                     sd_cmd_resp[127:96],    // arg
    //                     sd_cmd_resp[95:89],     // crc
    //                     sd_cmd_resp[88],        // stop bit
    //                 );
    //             `endif
    //
    //             state <= 0;
    //         end
    //     end
    //     endcase
    // end
    
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
    //         $display("Got response: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, stop: %b ]",
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
    wire[5:0] sim_cmdIndex = sim_cmdIn[45:40];
    reg[135:0] sim_respOut = 0;
    reg[7:0] sim_respLen = 0;
    reg sim_cmdOut = 1'bz;
    reg[7:0] sim_debug = 0;
    reg sim_acmd = 0;
    wire[6:0] sim_cmd = {sim_acmd, sim_cmdIndex};
    assign sd_cmd = sim_cmdOut;
    
    localparam CMD0     = {1'b0, 6'd0};     // GO_IDLE_STATE
    localparam CMD2     = {1'b0, 6'd2};     // ALL_SEND_CID
    localparam CMD3     = {1'b0, 6'd3};     // SEND_RELATIVE_ADDR
    localparam CMD6     = {1'b0, 6'd6};     // SWITCH_FUNC
    localparam ACMD6    = {1'b1, 6'd6};     // SWITCH_FUNC
    localparam CMD7     = {1'b0, 6'd7};     // SELECT_CARD/DESELECT_CARD
    localparam CMD8     = {1'b0, 6'd8};     // SEND_IF_COND
    localparam ACMD41   = {1'b1, 6'd41};    // SD_SEND_OP_COND
    localparam CMD55    = {1'b0, 6'd55};    // APP_CMD
    
    
    initial begin
        forever begin
            wait(sd_clk);
            if (!sd_cmd) begin
                // Receive command
                reg[7:0] i;
                for (i=0; i<48; i++) begin
                    wait(sd_clk);
                    sim_cmdIn = (sim_cmdIn<<1)|sd_cmd;
                    wait(!sd_clk);
                end
                
                $display("[SD CARD] Received command: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, stop: %b ]",
                    sim_cmdIn,
                    sim_cmdIn[47:46],   // preamble
                    sim_cmdIn[45:40],   // cmd
                    sim_cmdIn[39:8],    // arg
                    sim_cmdIn[7:1],     // crc
                    sim_cmdIn[0],       // stop bit
                );
                
                // Issue response if needed
                if (sim_cmdIndex) begin
                    case (sim_cmd)
                    CMD2:       begin sim_respOut=136'h3f0353445352313238808bb79d66014677; sim_respLen=136; end
                    CMD3:       begin sim_respOut=136'h03aaaa0520d1ffffffffffffffffffffff; sim_respLen=48;  end
                    CMD6:       begin sim_respOut=136'h0600000900ddffffffffffffffffffffff; sim_respLen=48;  end
                    ACMD6:      begin sim_respOut=136'h0600000920b9ffffffffffffffffffffff; sim_respLen=48;  end
                    CMD7:       begin sim_respOut=136'h070000070075ffffffffffffffffffffff; sim_respLen=48;  end
                    CMD8:       begin sim_respOut=136'h08000001aa13ffffffffffffffffffffff; sim_respLen=48;  end
                    ACMD41:     begin
                        if ($urandom % 2)   sim_respOut=136'h3f00ff8080ffffffffffffffffffffffff;
                        else                sim_respOut=136'h3fc1ff8080ffffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    CMD55:      begin sim_respOut=136'h370000012083ffffffffffffffffffffff; sim_respLen=48;  end
                    default:    begin  $display("[SD CARD] BAD COMMAND: %b", sim_cmd); $finish; end
                    endcase
                    
                    wait(sd_clk);
                    wait(!sd_clk);

                    wait(sd_clk);
                    wait(!sd_clk);

                    wait(sd_clk);
                    wait(!sd_clk);

                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    // sim_respOut = {2'b00, 6'b0, 32'b0, 7'b0, 1'b1};
                    $display("[SD CARD] Sending response: %b", sim_respOut);
                    for (i=0; i<sim_respLen; i++) begin
                        wait(!sd_clk);
                        sim_cmdOut = sim_respOut[135];
                        sim_respOut = sim_respOut<<1;
                        wait(sd_clk);
                    end
                end
                wait(!sd_clk);
                sim_cmdOut = 1'bz;
                
                // Note whether the next command is an application-specific command
                sim_acmd = (sim_cmdIndex==55);
            end
            wait(!sd_clk);
        end
    end
    
`endif
    
endmodule
