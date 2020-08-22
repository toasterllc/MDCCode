`include "../ClockGen.v"
`include "../SDCardInitializer.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`timescale 1ns/1ps










module Top(
`ifdef SIM
    output reg          clk12mhz = 0,
`else
    input wire          clk12mhz,
`endif
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
    wire sd_cmdIn;
    wire sd_cmdOut;
    wire sd_cmdOutActive;
    SDCardInitializer sdinit(
        .clk12mhz(clk12mhz),
        .sd_clk(sd_clk),
        .sd_cmdIn(sd_cmdIn),
        .sd_cmdOut(sd_cmdOut),
        .sd_cmdOutActive(sd_cmdOutActive)
    );
    
    // ====================
    // `sd_cmd` IO Pin
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_01), // Output=registered, OutputEnable=registered, input=direct
        // .PIN_TYPE(6'b1001_01), // Output=registered, OutputEnable=unregistered, input=direct
        .NEG_TRIGGER(1'b1)
    ) pin (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_CLK(clk),
        .OUTPUT_ENABLE(sd_cmdOutActive),
        .D_OUT_0(sd_cmdOut),
        .D_IN_0(sd_cmdIn)
    );
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
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
            clk12mhz = 0;
            #42;
            clk12mhz = 1;
            #42;
        end
    end
    
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
