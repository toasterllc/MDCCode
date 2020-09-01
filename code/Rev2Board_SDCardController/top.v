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
    
    output reg[3:0]    led = 0
);
`ifdef SIM
    reg clk12mhz = 0;
`endif
    
    // ====================
    // SD Card Controller
    // ====================
    reg sd_cmd_trigger = 0;
    reg sd_cmd_write = 0;
    reg[7:0] sd_cmd_addr = 0;
    // reg[13:0] sd_cmd_len = 0;
    wire[15:0] sd_dataOut;
    wire sd_dataOut_valid;
    
    // assign led = sd_dataOut[3:0];
    
    SDCardController sdcontroller(
        .clk(clk12mhz),
        
        // Command port
        .cmd_trigger(sd_cmd_trigger),
        .cmd_accepted(sd_cmd_accepted),
        .cmd_write(sd_cmd_write),
        .cmd_addr(sd_cmd_addr),
        // .cmd_len(sd_cmd_len),
        
        // Data-out port
        .dataOut(sd_dataOut),
        .dataOut_valid(sd_dataOut_valid),
        
        // SD port
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    reg[2:0] state = 0;
    always @(posedge clk12mhz) begin
        case (state)
        0: begin
            sd_cmd_trigger <= 1;
            // sd_cmd_len <= 2;
            sd_cmd_write <= 1;
            
            if (sd_cmd_accepted) begin
                $display("[SD HOST] Controller accepted command (#1)");
                state <= 1;
            end
        end
        
        1: begin
            if (sd_cmd_accepted) begin
                $display("[SD HOST] Controller accepted command (#2)");
                state <= 2;
            end
        end
        
        2: begin
            sd_cmd_trigger <= 0;
            if (sd_cmd_accepted) begin
                $display("[SD HOST] Controller accepted command (#3)");
                state <= 3;
            end
        end
        
        3: begin
        end
        endcase
        
        if (sd_dataOut_valid) begin
            $display("GOT DATA: %h", sd_dataOut);
            led <= sd_dataOut;
        end
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
    reg[47:0] sim_respOut = 0;
    reg[7:0] sim_respLen = 0;
    
    reg sim_cmdOut = 1'bz;
    assign sd_cmd = sim_cmdOut;
    
    reg[7:0] sim_debug = 0;
    reg sim_acmd = 0;
    wire[6:0] sim_cmd = {sim_acmd, sim_cmdIndex};
    
    // localparam READ_DATA = {{4092{1'b0}}, 4'b1111};
    // localparam PAYLOAD_DATA = {4096{1'b1}};
    localparam PAYLOAD_DATA = {128{32'h42434445}};
    localparam CRC_DATA = 16'hEDA9;
    reg[3:0] sim_datOut = 4'bzzzz;
    reg[4095:0] sim_payloadDataReg = 0;
    reg[15:0] sim_crcDataReg = 0;
    assign sd_dat = sim_datOut;
    
    
    reg sim_sendData = 0;
    
    localparam CMD0     = {1'b0, 6'd0};     // GO_IDLE_STATE
    localparam CMD12    = {1'b0, 6'd12};    // STOP_TRANSMISSION
    localparam CMD18    = {1'b0, 6'd18};    // READ_MULTIPLE_BLOCK
    
    initial begin
        forever begin
            sim_cmdInCRCRst_ = 0;
            
            wait(sd_clk);
            if (!sd_cmd) begin
                // Receive command
                reg[7:0] i;
                reg[7:0] count;
                
                // Start calculating CRC for incoming command
                sim_cmdInCRCRst_ = 1;
                
                for (i=0; i<48; i++) begin
                    wait(sd_clk);
                    sim_cmdIn = (sim_cmdIn<<1)|sd_cmd;
                    wait(!sd_clk);
                    
                    if (i == 39) begin
                        // $display("[SD CARD] MEOW CRC: %b", sim_cmdInCRC);
                        // $finish;
                        sim_ourCRC = sim_cmdInCRC;
                        sim_cmdInCRCRst_ = 0;
                    end
                end
                
                $display("[SD CARD] Received command: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, stop: %b ]",
                    sim_cmdIn,
                    sim_cmdIn[47:46],   // preamble
                    sim_cmdIn[45:40],   // cmd
                    sim_cmdIn[39:8],    // arg
                    sim_cmdIn[7:1],     // crc
                    sim_cmdIn[0],       // stop bit
                );
                
                if (sim_cmdIn[7:1] === sim_ourCRC) begin
                    $display("[SD CARD] ^^^ CRC Valid ✅");
                end else begin
                    $display("[SD CARD] ^^^ Bad CRC: ours=%b, theirs=%b ❌", sim_ourCRC, sim_cmdIn[7:1]);
                end
                
                // Issue response if needed
                if (sim_cmdIndex) begin
                    case (sim_cmd)
                    // TODO: make this a real CMD12 response. right now it's a CMD3 response.
                    CMD12:      begin sim_respOut=48'h03aaaa0520d1; sim_respLen=48;  end
                    // TODO: make this a real CMD18 response. right now it's a CMD3 response.
                    CMD18:      begin sim_respOut=48'h03aaaa0520d1; sim_respLen=48;  end
                    default:    begin  $display("[SD CARD] BAD COMMAND: %b", sim_cmd); $finish; end
                    endcase
                    
                    // Wait a random number of clocks before providing response
                    count = $urandom%10;
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    // sim_respOut = {2'b00, 6'b0, 32'b0, 7'b0, 1'b1};
                    $display("[SD CARD] Sending response: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, stop: %b ]",
                        sim_respOut,
                        sim_respOut[47:46],     // preamble
                        sim_respOut[45:40],     // cmd
                        sim_respOut[39:8],      // arg
                        sim_respOut[7:1],       // crc
                        sim_respOut[0],         // stop bit
                    );
                    
                    for (i=0; i<sim_respLen; i++) begin
                        wait(!sd_clk);
                        sim_cmdOut = sim_respOut[47];
                        sim_respOut = sim_respOut<<1;
                        wait(sd_clk);
                    end
                end
                wait(!sd_clk);
                sim_cmdOut = 1'bz;
                
                if (sim_cmdIndex == 12) begin
                    sim_sendData = 0;
                end else if (sim_cmdIndex == 18) begin
                    sim_sendData = 1;
                end
            end
            wait(!sd_clk);
        end
    end
    
    
    
    
    
    
    // ====================
    // CRC (CMD)
    // ====================
    reg sim_cmdInCRCRst_ = 0;
    wire[6:0] sim_cmdInCRC;
    reg[6:0] sim_ourCRC = 0;
    CRC7 crc7(
        .clk(sd_clk),
        .rst_(sim_cmdInCRCRst_),
        .din(sim_cmdIn[0]),
        .dout(),
        .doutNext(sim_cmdInCRC)
    );
    
    // ====================
    // CRC (DAT[3:0])
    // ====================
    reg sim_datCRCRst_ = 0;
    wire[15:0] sim_crc[3:0];
    reg[15:0] sim_crcReg[3:0];
    genvar geni;
    for (geni=0; geni<4; geni=geni+1) begin
        CRC16 crc16(
            .clk(sd_clk),
            .rst_(sim_datCRCRst_),
            .din(sd_dat[geni]),
            .dout(),
            .doutNext(sim_crc[geni])
        );
    end
    
    // TODO: start response data while command response is still being sent
    initial begin
        forever begin
            sim_datCRCRst_ = 0;
            wait(sd_clk);
            if (sim_sendData) begin
                reg[15:0] i = 0;
                
                // Start bit
                wait(!sd_clk);
                sim_datOut = 4'b0000;
                wait(sd_clk);
                
                wait(!sd_clk);
                sim_datCRCRst_ = 1;

                // Shift out data
                sim_payloadDataReg = PAYLOAD_DATA;
                $display("[SD CARD] Sending data: %h", sim_payloadDataReg);
                
                for (i=0; i<1024 && sim_sendData; i++) begin
                    wait(!sd_clk);
                    sim_datOut = sim_payloadDataReg[4095:4092];
                    sim_payloadDataReg = sim_payloadDataReg<<4;
                    wait(sd_clk);
                end
                
                if (sim_sendData) begin
                    sim_crcReg[3] = sim_crc[3];
                    sim_crcReg[2] = sim_crc[2];
                    sim_crcReg[1] = sim_crc[1];
                    sim_crcReg[0] = sim_crc[0];

                    // $display("[SD CARD] CRC3: %h", sim_crc[3]);
                    // $display("[SD CARD] CRC2: %h", sim_crc[2]);
                    // $display("[SD CARD] CRC1: %h", sim_crc[1]);
                    // $display("[SD CARD] CRC0: %h", sim_crc[0]);

                    // Shift out CRC
                    sim_crcDataReg = CRC_DATA;
                    
                    for (i=0; i<16 && sim_sendData; i++) begin
                        wait(!sd_clk);
                        sim_datOut = {sim_crcReg[3][15], sim_crcReg[2][15], sim_crcReg[1][15], sim_crcReg[0][15]};

                        sim_crcReg[3] = sim_crcReg[3]<<1;
                        sim_crcReg[2] = sim_crcReg[2]<<1;
                        sim_crcReg[1] = sim_crcReg[1]<<1;
                        sim_crcReg[0] = sim_crcReg[0]<<1;
                        wait(sd_clk);
                    end
                end
                
                // End bit
                wait(!sd_clk);
                sim_datOut = 4'b1111;
                wait(sd_clk);
                
                // Stop driving DAT lines
                wait(!sd_clk);
                sim_datOut = 4'bzzzz;
                wait(sd_clk);
                
                wait(!sd_clk);
                wait(sd_clk);
                
                wait(!sd_clk);
                wait(sd_clk);
            end
            
            wait(!sd_clk);
        end
    end
`endif
endmodule
