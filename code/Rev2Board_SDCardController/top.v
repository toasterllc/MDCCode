`include "../SDCardController.v"
`include "../ClockGen.v"

`timescale 1ns/1ps

module Top(
`ifndef SIM
    input wire          clk12mhz,
`endif

    output wire         sd_clk  /* synthesis syn_keep=1 */,
    
`ifdef SIM
    inout tri1          sd_cmd  /* synthesis syn_keep=1 */,
`else
    inout wire          sd_cmd  /* synthesis syn_keep=1 */,
`endif
    
`ifdef SIM
    inout tri1[3:0]     sd_dat  /* synthesis syn_keep=1 */,
`else
    inout wire[3:0]     sd_dat  /* synthesis syn_keep=1 */,
`endif
    
    output wire[3:0]    led
);
`ifdef SIM
    reg clk12mhz = 0;
`endif
    
    // ====================
    // SD Card Controller
    // ====================
    reg sd_cmd_trigger = 0;
    reg sd_cmd_write = 0;
    reg[31:0] sd_cmd_addr = 0;
    reg[13:0] sd_cmd_len = 0;
    wire[15:0] sd_dataOut;
    wire sd_dataOut_valid;
    
    assign led = sd_dataOut[3:0];

    SDCardController sdcontroller(
        .clk(clk12mhz),
        
        // Command port
        .cmd_trigger(sd_cmd_trigger),
        .cmd_write(sd_cmd_write),
        .cmd_addr(sd_cmd_addr),
        .cmd_len(sd_cmd_len),
        
        // Data-out port
        .dataOut(sd_dataOut),
        .dataOut_valid(sd_dataOut_valid),
        
        // SD port
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );

    always @(posedge clk12mhz) begin
        sd_cmd_trigger <= 1;
        sd_cmd_write <= 0;
    end
    
    // assign led = {counter[21:19], counter[0]};
    // reg[21:0] counter;
    // always @(posedge clk12mhz) begin
    //     counter <= counter+1;
    // end
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
    end
    
    initial begin
        forever begin
            clk12mhz = 0;
            #42;
            clk12mhz = 1;
            #42;
        end
    end
    
    initial begin
        #1000000;
        $finish;
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
    assign sd_cmd = sim_cmdOut;
    
    reg[7:0] sim_debug = 0;
    reg sim_acmd = 0;
    wire[6:0] sim_cmd = {sim_acmd, sim_cmdIndex};
    
    // localparam READ_DATA = {{4092{1'b0}}, 4'b1111};
    localparam PAYLOAD_DATA = {4096{1'b1}};
    localparam CRC_DATA = 16'hEDA9;
    reg[3:0] sim_datOut = 4'bzzzz;
    reg[4095:0] sim_payloadDataReg = 0;
    reg[15:0] sim_crcDataReg = 0;
    assign sd_dat = sim_datOut;
    
    localparam CMD0     = {1'b0, 6'd0};     // GO_IDLE_STATE
    localparam CMD18    = {1'b0, 6'd18};    // GO_IDLE_STATE
    
    initial begin
        forever begin
            wait(sd_clk);
            if (!sd_cmd) begin
                // Receive command
                reg[7:0] i;
                reg[7:0] count;
                
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
                    // TODO: make this a real CMD18 response. right now it's a CMD3 response.
                    CMD18:      begin sim_respOut=136'h03aaaa0520d1ffffffffffffffffffffff; sim_respLen=48;  end
                    default:    begin  $display("[SD CARD] BAD COMMAND: %b", sim_cmd); $finish; end
                    endcase
                    
                    // Wait a random number of clocks before providing response
                    count = $urandom%10;
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
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
                
                // TODO: start response data while command response is still being sent
                if (sim_cmdIndex == 18) begin
                    // Start bit
                    wait(!sd_clk);
                    sim_datOut = 4'b0000;
                    wait(sd_clk);
                    
                    // Shift out data
                    repeat (1) begin
                        sim_payloadDataReg = PAYLOAD_DATA;
                        $display("[SD CARD] Sending data: %h", sim_payloadDataReg);
                        
                        repeat (1024) begin
                            wait(!sd_clk);
                            sim_datOut = sim_payloadDataReg[4095:4092];
                            sim_payloadDataReg = sim_payloadDataReg<<4;
                            wait(sd_clk);
                        end
                    end
                    
                    // Shift out CRC
                    sim_crcDataReg = CRC_DATA;
                    repeat (16) begin
                        wait(!sd_clk);
                        sim_datOut = {4{sim_crcDataReg[15]}};
                        sim_crcDataReg = sim_crcDataReg<<1;
                        wait(sd_clk);
                    end
                    
                    // End bit
                    wait(!sd_clk);
                    sim_datOut = 4'b1111;
                    wait(sd_clk);
                    
                    // Stop driving DAT lines
                    wait(!sd_clk);
                    sim_datOut = 4'bzzzz;
                    wait(sd_clk);
                end
            end
            wait(!sd_clk);
        end
    end
`endif
endmodule
