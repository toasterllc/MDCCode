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
    // 180 MHz clock
    wire clk;
    ClockGen #(
        .FREQ(180000000),
		.DIVR(0),
		.DIVF(59),
		.DIVQ(2),
		.FILTER_RANGE(1)
    ) cg(.clk12mhz(clk12mhz), .clk(clk));
    
    // ====================
    // SD Card Controller
    // ====================
    reg sd_cmd_trigger = 0;
    reg sd_cmd_write = 0;
    reg[22:0] sd_cmd_writeLen = 0;
    reg[7:0] sd_cmd_addr = 0;
    reg[15:0] sd_dataIn = 16'h0;
    wire sd_dataIn_accepted;
    wire[15:0] sd_dataOut;
    wire sd_dataOut_valid;
    
    // assign led = sd_dataOut[3:0];
    
    SDCardController sdcontroller(
        .clk(clk),
        
        // Command port
        .cmd_trigger(sd_cmd_trigger),
        .cmd_accepted(sd_cmd_accepted),
        .cmd_write(sd_cmd_write),
        .cmd_writeLen(sd_cmd_writeLen),
        .cmd_addr(32'b0|sd_cmd_addr),
        // .cmd_len(sd_cmd_len),
        
        // Data-in port
        .dataIn(sd_dataIn),
        .dataIn_accepted(sd_dataIn_accepted),
        
        // Data-out port
        .dataOut(sd_dataOut),
        .dataOut_valid(sd_dataOut_valid),
        
        // SD port
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    reg[3:0] state = 0;
    
    // ====================
    // State Machine
    //   Toggle between reading/writing blocks
    // ====================
    always @(posedge clk) begin
        case (state)
        0: begin
            sd_cmd_trigger <= 1;
            if (sd_cmd_accepted) begin
                if (sd_cmd_write) begin
                    $display("[SD HOST] Write accepted");
                end else begin
                    $display("[SD HOST] Read accepted");
                end
                state <= 1;
            end
        end
        
        1: begin
            sd_cmd_trigger <= 0;
            if (sd_cmd_accepted) begin
                $display("[SD HOST] Stop accepted");
                sd_cmd_write <= !sd_cmd_write;
                state <= 0;
            end
        end
        endcase
        
        if (sd_dataOut_valid) begin
            $display("[SD HOST] Got read data: %h", sd_dataOut);
            led <= sd_dataOut;
        end
    end
    
    // // ====================
    // // State Machine
    // //   Read 2 blocks, write 2 blocks
    // // ====================
    // always @(posedge clk) begin
    //     case (state)
    //     0: begin
    //         sd_cmd_trigger <= 1;
    //         // sd_cmd_len <= 2;
    //         sd_cmd_write <= 0;
    //         // Wait until read is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Read accepted");
    //             state <= 1;
    //         end
    //     end
    //
    //     1: begin
    //         // Wait until read is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Read accepted (#2)");
    //             state <= 2;
    //         end
    //     end
    //
    //     2: begin
    //         sd_cmd_trigger <= 0;
    //         // Wait until stop is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Stop accepted");
    //             state <= 3;
    //         end
    //     end
    //
    //     3: begin
    //         // Write 1 block
    //         sd_cmd_trigger <= 1;
    //         sd_cmd_write <= 1;
    //         // Wait until write is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Write accepted");
    //             state <= 4;
    //         end
    //     end
    //
    //     4: begin
    //         if (sd_dataIn_accepted) begin
    //             sd_dataIn <= ~sd_dataIn;
    //         end
    //
    //         // Wait until write is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Write accepted (#2)");
    //             state <= 5;
    //         end
    //     end
    //
    //     5: begin
    //         if (sd_dataIn_accepted) begin
    //             sd_dataIn <= ~sd_dataIn;
    //         end
    //
    //         // Stop writing
    //         sd_cmd_trigger <= 0;
    //         // Wait until stop is accepted
    //         if (sd_cmd_accepted) begin
    //             $display("[SD HOST] Stop accepted");
    //             $display("[SD HOST] DONE ✅");
    //             state <= 6;
    //         end
    //     end
    //
    //     6: begin
    //     end
    //     endcase
    //
    //     if (sd_dataOut_valid) begin
    //         $display("[SD HOST] Got read data: %h", sd_dataOut);
    //         led <= sd_dataOut;
    //     end
    // end
    
    // assign led = {counter[21:19], counter[0]};
    // reg[21:0] counter;
    // always @(posedge clk) begin
    //     counter <= counter+1;
    // end
    
`ifdef SIM
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Top);
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
    
    reg sim_acmd = 0;
    wire[6:0] sim_cmd = {sim_acmd, sim_cmdIndex};
    
    localparam PAYLOAD_DATA = {4096{1'b1}};
    // localparam PAYLOAD_DATA = {128{32'h42434445}};
    reg[3:0] sim_datOut = 4'bzzzz;
    reg[4095:0] sim_payloadDataReg = 0;
    assign sd_dat = sim_datOut;
    
    reg sim_recvWriteData = 0;
    reg sim_sendReadData = 0;
    
    localparam CMD0     = {1'b0, 6'd0};     // GO_IDLE_STATE
    localparam CMD12    = {1'b0, 6'd12};    // STOP_TRANSMISSION
    localparam CMD18    = {1'b0, 6'd18};    // READ_MULTIPLE_BLOCK
    localparam CMD25    = {1'b0, 6'd25};    // WRITE_MULTIPLE_BLOCK
    localparam CMD55    = {1'b0, 6'd55};    // APP_CMD
    
    localparam ACMD23   = {1'b1, 6'd23};    // SET_WR_BLK_ERASE_COUNT
    
    initial begin
        reg halla;
        halla = 0;
        
        forever begin
            sim_cmdInCRCRst_ = 0;
            
            wait(sd_clk);
            if (!sd_cmd) begin
                // Receive command
                reg[7:0] i;
                reg[7:0] count;
                reg signalBusy;
                
                signalBusy = 0;
                
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
                
                $display("[SD CARD] Received command: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                    sim_cmdIn,
                    sim_cmdIn[47:46],   // preamble
                    sim_cmdIn[45:40],   // cmd
                    sim_cmdIn[39:8],    // arg
                    sim_cmdIn[7:1],     // crc
                    sim_cmdIn[0],       // end bit
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
                    // TODO: make this a real CMD18 response. right now it's a CMD3 response.
                    CMD25:      begin sim_respOut=48'h03aaaa0520d1; sim_respLen=48;  end
                    // TODO: make this a real CMD55 response. right now it's a CMD3 response.
                    CMD55:      begin sim_respOut=48'h03aaaa0520d1; sim_respLen=48;  end
                    // TODO: make this a real ACMD23 response. right now it's a CMD3 response.
                    ACMD23:     begin sim_respOut=48'h03aaaa0520d1; sim_respLen=48;  end
                    default:    begin  $display("[SD CARD] BAD COMMAND: CMD%0d", sim_cmd); $finish; end
                    endcase
                    
                    // Signal busy (DAT=0) if we were previously writing,
                    // and we received the stop command
                    signalBusy = (sim_cmdIndex===12 && sim_recvWriteData);
                    if (signalBusy) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        sim_datOut[0] = 0;
                    end
                    
                    // Wait a random number of clocks before providing response
                    count = $urandom%10;
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    // sim_respOut = {2'b00, 6'b0, 32'b0, 7'b0, 1'b1};
                    $display("[SD CARD] Sending response: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                        sim_respOut,
                        sim_respOut[47:46],     // preamble
                        sim_respOut[45:40],     // cmd
                        sim_respOut[39:8],      // arg
                        sim_respOut[7:1],       // crc
                        sim_respOut[0],         // end bit
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
                
                // Note whether the next command is an application-specific command
                sim_acmd = (sim_cmdIndex==55);
                // TODO: if we were writing, signal busy for a random number of cycles
                if (sim_cmdIndex == 12) begin
                    sim_recvWriteData = 0;
                    sim_sendReadData = 0;
                end else if (sim_cmdIndex == 25) begin
                    sim_recvWriteData = 1;
                end else if (sim_cmdIndex == 18) begin
                    sim_sendReadData = 1;
                end
                
                // Stop signaling busy, if we were signaling busy
                if (signalBusy) begin
                    // Wait a random number of clocks before de-asserting busy
                    count = $urandom%10;
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    sim_datOut[0] = 1'bz;
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
    wire[15:0] sim_crcNext[3:0];
    reg[15:0] sim_ourCRCReg[3:0];
    reg[15:0] sim_theirCRCReg[3:0];
    genvar geni;
    for (geni=0; geni<4; geni=geni+1) begin
        CRC16 crc16(
            .clk(sd_clk),
            .rst_(sim_datCRCRst_),
            .din(sd_dat[geni]),
            .dout(sim_crc[geni]),
            .doutNext(sim_crcNext[geni])
        );
    end
    
    
    
    // ====================
    // Handle writing to the card
    // ====================
    initial begin
        forever begin
            wait(sd_clk);
            if (sim_recvWriteData) begin
                reg[15:0] i;
                reg[7:0] count;
                
                // Wait for start bit
                while (sd_dat[0] && sim_recvWriteData) begin
                    wait(!sd_clk);
                    wait(sd_clk);
                end
                wait(!sd_clk);
                
                sim_datCRCRst_ = 1;
                
                for (i=0; i<1024 && sim_recvWriteData; i++) begin
                    wait(sd_clk);
                    sim_payloadDataReg = (sim_payloadDataReg<<4)|sd_dat[3:0];
                    wait(!sd_clk);
                end
                
                if (sim_recvWriteData) begin
                    $display("[SD CARD] Received write data: %h", sim_payloadDataReg);
                end
                
                if (sim_recvWriteData) begin
                    sim_ourCRCReg[3] = sim_crc[3];
                    sim_ourCRCReg[2] = sim_crc[2];
                    sim_ourCRCReg[1] = sim_crc[1];
                    sim_ourCRCReg[0] = sim_crc[0];
                    sim_datCRCRst_ = 0;
                end
                
                for (i=0; i<16 && sim_recvWriteData; i++) begin
                    wait(sd_clk);
                    sim_theirCRCReg[3] = (sim_theirCRCReg[3]<<1)|sd_dat[3];
                    sim_theirCRCReg[2] = (sim_theirCRCReg[2]<<1)|sd_dat[2];
                    sim_theirCRCReg[1] = (sim_theirCRCReg[1]<<1)|sd_dat[1];
                    sim_theirCRCReg[0] = (sim_theirCRCReg[0]<<1)|sd_dat[0];
                    wait(!sd_clk);
                end
                
                // Check CRCs
                if (sim_recvWriteData) begin
                    if (sim_ourCRCReg[3] !== sim_theirCRCReg[3]) begin
                        $display("[SD CARD] DAT3: Bad CRC (ours=%h, theirs=%h) ❌", sim_ourCRCReg[3], sim_theirCRCReg[3]);
                    end else begin
                        $display("[SD CARD] DAT3: CRC Valid (ours=%h, theirs=%h) ✅", sim_ourCRCReg[3], sim_theirCRCReg[3]);
                    end
                    
                    if (sim_ourCRCReg[2] !== sim_theirCRCReg[2]) begin
                        $display("[SD CARD] DAT2: Bad CRC (ours=%h, theirs=%h) ❌", sim_ourCRCReg[2], sim_theirCRCReg[2]);
                    end else begin
                        $display("[SD CARD] DAT2: CRC Valid (ours=%h, theirs=%h) ✅", sim_ourCRCReg[2], sim_theirCRCReg[2]);
                    end
                    
                    if (sim_ourCRCReg[1] !== sim_theirCRCReg[1]) begin
                        $display("[SD CARD] DAT1: Bad CRC (ours=%h, theirs=%h) ❌", sim_ourCRCReg[1], sim_theirCRCReg[1]);
                    end else begin
                        $display("[SD CARD] DAT1: CRC Valid (ours=%h, theirs=%h) ✅", sim_ourCRCReg[1], sim_theirCRCReg[1]);
                    end
                    
                    if (sim_ourCRCReg[0] !== sim_theirCRCReg[0]) begin
                        $display("[SD CARD] DAT0: Bad CRC (ours=%h, theirs=%h) ❌", sim_ourCRCReg[0], sim_theirCRCReg[0]);
                    end else begin
                        $display("[SD CARD] DAT0: CRC Valid (ours=%h, theirs=%h) ✅", sim_ourCRCReg[0], sim_theirCRCReg[0]);
                    end
                end
                
                // Check end bits
                if (sim_recvWriteData) begin
                    wait(sd_clk);
                    if (!sd_dat[3]) begin
                        $display("[SD CARD] DAT3: Bad end bit: %b ❌", sd_dat[3]);
                    end else begin
                        $display("[SD CARD] DAT3: End bit OK ✅");
                    end
                    
                    if (!sd_dat[2]) begin
                        $display("[SD CARD] DAT2: Bad end bit: %b ❌", sd_dat[2]);
                    end else begin
                        $display("[SD CARD] DAT2: End bit OK ✅");
                    end
                    
                    if (!sd_dat[1]) begin
                        $display("[SD CARD] DAT1: Bad end bit: %b ❌", sd_dat[1]);
                    end else begin
                        $display("[SD CARD] DAT1: End bit OK ✅");
                    end
                    
                    if (!sd_dat[0]) begin
                        $display("[SD CARD] DAT0: Bad end bit: %b ❌", sd_dat[0]);
                    end else begin
                        $display("[SD CARD] DAT0: End bit OK ✅");
                    end
                    wait(!sd_clk);
                end
                
                // Send CRC status token
                if (sim_recvWriteData) begin
                    // Wait 2 cycles before sending CRC status
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    sim_datOut = 4'b0000;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    sim_datOut = 4'b0000;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    sim_datOut = 4'b0001;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    sim_datOut = 4'b0000;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    sim_datOut = 4'b0001;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    // Send busy signal for a random number of cycles
                    count = $urandom%10;
                    if (count) begin
                        // Start bit
                        sim_datOut = 4'b0000;
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        for (i=0; i<count; i++) begin
                            wait(sd_clk);
                            wait(!sd_clk);
                        end
                        
                        // End bit
                        sim_datOut = 4'b0001;
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    sim_datOut = 4'bzzzz;
                end
                
                sim_datCRCRst_ = 0;
            end

            wait(!sd_clk);
        end
    end
    
    
    // ====================
    // Handle reading from the card
    // ====================
    // TODO: start response data while command response is still being sent
    initial begin
        forever begin
            wait(sd_clk);
            if (sim_sendReadData) begin
                reg[15:0] i;
                
                // Start bit
                wait(!sd_clk);
                sim_datOut = 4'b0000;
                wait(sd_clk);
                
                wait(!sd_clk);
                sim_datCRCRst_ = 1;

                // Shift out data
                sim_payloadDataReg = PAYLOAD_DATA;
                $display("[SD CARD] Sending read data: %h", sim_payloadDataReg);
                
                for (i=0; i<1024 && sim_sendReadData; i++) begin
                    wait(!sd_clk);
                    sim_datOut = sim_payloadDataReg[4095:4092];
                    sim_payloadDataReg = sim_payloadDataReg<<4;
                    wait(sd_clk);
                end
                
                if (sim_sendReadData) begin
                    sim_ourCRCReg[3] = sim_crcNext[3];
                    sim_ourCRCReg[2] = sim_crcNext[2];
                    sim_ourCRCReg[1] = sim_crcNext[1];
                    sim_ourCRCReg[0] = sim_crcNext[0];
                    
                    $display("[SD CARD] CRC3: %h", sim_crcNext[3]);
                    $display("[SD CARD] CRC2: %h", sim_crcNext[2]);
                    $display("[SD CARD] CRC1: %h", sim_crcNext[1]);
                    $display("[SD CARD] CRC0: %h", sim_crcNext[0]);
                    
                    // Shift out CRC
                    for (i=0; i<16 && sim_sendReadData; i++) begin
                        wait(!sd_clk);
                        sim_datOut = {sim_ourCRCReg[3][15], sim_ourCRCReg[2][15], sim_ourCRCReg[1][15], sim_ourCRCReg[0][15]};
                        
                        sim_ourCRCReg[3] = sim_ourCRCReg[3]<<1;
                        sim_ourCRCReg[2] = sim_ourCRCReg[2]<<1;
                        sim_ourCRCReg[1] = sim_ourCRCReg[1]<<1;
                        sim_ourCRCReg[0] = sim_ourCRCReg[0]<<1;
                        wait(sd_clk);
                    end
                end
                
                sim_datCRCRst_ = 0;
                
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
