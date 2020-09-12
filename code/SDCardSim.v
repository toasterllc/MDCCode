module SDCardSim(
    input wire      sd_clk,
    inout wire      sd_cmd,
    inout wire[3:0] sd_dat
);
    // ====================
    // SD card emulator
    //   Receive commands, issue responses
    // ====================
    reg[47:0] sim_cmdIn = 0;
    reg[1:0] sim_cmdIn_preamble = 0;
    reg[5:0] sim_cmdIn_cmdIndex = 0;
    reg[31:0] sim_cmdIn_arg = 0;
    reg[6:0] sim_cmdIn_theirCRC = 0;
    reg[0:0] sim_cmdIn_endBit = 0;
    reg[15:0] sim_cmdIn_rca = 0;
    reg[135:0] sim_respOut = 0;
    reg[7:0] sim_respLen = 0;
    
    reg[15:0] sim_rca = 16'h0000;
    
    reg sim_cmdOut = 1'bz;
    assign sd_cmd = sim_cmdOut;
    
    reg sim_acmd = 0;
    wire[6:0] sim_cmd = {sim_acmd, sim_cmdIn_cmdIndex};
    
    localparam PAYLOAD_DATA = {4096{1'b0}};
    // localparam PAYLOAD_DATA = {4096{1'b1}};
    // localparam PAYLOAD_DATA = {128{32'h42434445}};
    // localparam PAYLOAD_DATA = {128{32'hFF00FF00}};
    reg[3:0] sim_datOut = 4'bzzzz;
    reg[4095:0] sim_payloadDataReg = 0;
    assign sd_dat = sim_datOut;
    
    reg sim_recvWriteData = 0;
    reg sim_sendReadData = 0;
    
    
    localparam CMD0     = {1'b0, 6'd0};     // GO_IDLE_STATE
    localparam CMD2     = {1'b0, 6'd2};     // ALL_SEND_CID
    localparam CMD3     = {1'b0, 6'd3};     // SEND_RELATIVE_ADDR
    localparam CMD6     = {1'b0, 6'd6};     // SWITCH_FUNC
    localparam CMD7     = {1'b0, 6'd7};     // SELECT_CARD/DESELECT_CARD
    localparam CMD8     = {1'b0, 6'd8};     // SEND_IF_COND
    localparam CMD11    = {1'b0, 6'd11};    // VOLTAGE_SWITCH
    localparam CMD12    = {1'b0, 6'd12};    // STOP_TRANSMISSION
    localparam CMD18    = {1'b0, 6'd18};    // READ_MULTIPLE_BLOCK
    localparam CMD25    = {1'b0, 6'd25};    // WRITE_MULTIPLE_BLOCK
    localparam CMD55    = {1'b0, 6'd55};    // APP_CMD
    
    localparam ACMD6    = {1'b1, 6'd6};     // SWITCH_FUNC
    localparam ACMD23   = {1'b1, 6'd23};    // SET_WR_BLK_ERASE_COUNT
    localparam ACMD41   = {1'b1, 6'd41};    // SD_SEND_OP_COND
    
    always @(posedge sd_clk) begin
        sim_cmdIn <= (sim_cmdIn<<1)|sd_cmd;
    end
    
    
    
    
    
    // ====================
    // CRC (CMD)
    // ====================
    reg sim_cmdIn_ourCRC_rst_ = 0;
    wire[6:0] sim_cmdIn_ourCRC;
    reg[6:0] sim_cmdIn_ourCRCReg = 0;
    CRC7 CRC7_cmdIn(
        .clk(sd_clk),
        .rst_(sim_cmdIn_ourCRC_rst_),
        .din(sim_cmdIn[0]),
        .dout(sim_cmdIn_ourCRC),
        .doutNext()
    );
    
    
    
    
    // ====================
    // CRC (DAT[3:0])
    // ====================
    reg sim_dat_crcRst_ = 0;
    wire[15:0] sim_dat_crc[3:0];
    wire[15:0] sim_dat_crcNext[3:0];
    reg[15:0] sim_dat_ourCRCReg[3:0];
    reg[15:0] sim_dat_theirCRCReg[3:0];
    genvar geni;
    for (geni=0; geni<4; geni=geni+1) begin
        CRC16 crc16(
            .clk(sd_clk),
            .rst_(sim_dat_crcRst_),
            .din(sd_dat[geni]),
            .dout(sim_dat_crc[geni]),
            .doutNext(sim_dat_crcNext[geni])
        );
    end
    
    
    
    
    
    initial begin
        reg halla;
        halla = 0;
        
        forever begin
            sim_cmdIn_ourCRC_rst_ = 0;
            
            wait(sd_clk);
            if (!sd_cmd) begin
                // Receive command
                reg[7:0] i;
                reg[7:0] count;
                reg signalBusy;
                
                wait(!sd_clk);
                signalBusy = 0;
                
                // Start calculating CRC for incoming command
                sim_cmdIn_ourCRC_rst_ = 1;
                
                for (i=0; i<47; i++) begin
                    wait(sd_clk);
                    wait(!sd_clk);
                    if (i == 39) begin
                        sim_cmdIn_ourCRCReg = sim_cmdIn_ourCRC;
                        sim_cmdIn_ourCRC_rst_ = 0;
                    end
                end
                
                // Remember our command index/argument/RCA
                sim_cmdIn_preamble = sim_cmdIn[47:46];
                sim_cmdIn_cmdIndex = sim_cmdIn[45:40];
                sim_cmdIn_arg = sim_cmdIn[39:8];
                sim_cmdIn_theirCRC = sim_cmdIn[7:1];
                sim_cmdIn_rca = sim_cmdIn_arg[31:16];
                sim_cmdIn_endBit = sim_cmdIn[0];
                
                $display("[SD CARD] Received command: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                    sim_cmdIn,
                    sim_cmdIn_preamble,     // preamble
                    sim_cmdIn_cmdIndex,     // cmd
                    sim_cmdIn_arg,          // arg
                    sim_cmdIn_theirCRC,     // crc
                    sim_cmdIn_endBit,       // end bit
                );
                
                if (sim_cmdIn_preamble !== 2'b01) begin
                    $display("[SD CARD] Bad preamble: %b ❌", sim_cmdIn_preamble);
                    `finish;
                end
                
                if (sim_cmdIn_theirCRC === sim_cmdIn_ourCRCReg) begin
                    $display("[SD CARD] ^^^ CRC Valid ✅");
                end else begin
                    $display("[SD CARD] ^^^ Bad CRC: ours=%b, theirs=%b ❌", sim_cmdIn_ourCRCReg, sim_cmdIn[7:1]);
                    `finish;
                end
                
                if (sim_cmdIn_endBit !== 1'b1) begin
                    $display("[SD CARD] Bad end bit: %b ❌", sim_cmdIn_endBit);
                    `finish;
                end
                
                // Issue response if needed
                if (sim_cmdIn_cmdIndex) begin
                    case (sim_cmd)
                    
                    CMD2: begin
                        sim_respOut=136'h3f0353445352313238808bb79d66014677;
                        sim_respLen=136;
                    end
                    
                    CMD3: begin
                        sim_rca = 16'hAAAA;
                        sim_respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD6: begin
                        sim_respOut=136'h0600000900ddffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD7: begin
                        if (sim_cmdIn_rca !== sim_rca) begin
                            $display("[SD CARD] CMD7: Bad RCA received: %h ❌", sim_cmdIn_rca);
                            `finish;
                        end
                        sim_respOut=136'h070000070075ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD8: begin
                        sim_respOut=136'h08000001aa13ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD11: begin
                        sim_respOut=136'h0B0000070081ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD12: begin
                        // TODO: make this a real CMD12 response. right now it's a CMD3 response.
                        sim_respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD18: begin
                        // TODO: make this a real CMD18 response. right now it's a CMD3 response.
                        sim_respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD25: begin
                        // TODO: make this a real CMD18 response. right now it's a CMD3 response.
                        sim_respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    CMD55: begin
                        if (sim_cmdIn_rca !== sim_rca) begin
                            $display("[SD CARD] CMD55: Bad RCA received: %h ❌", sim_cmdIn_rca);
                            `finish;
                        end
                        sim_respOut=136'h370000012083ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    ACMD6: begin
                        sim_respOut=136'h0600000920b9ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    ACMD23: begin
                        if (!sim_cmdIn_arg[22:0]) begin
                            $display("[SD CARD] ACMD23: Zero block count received ❌");
                            `finish;
                        end
                        // TODO: make this a real ACMD23 response. right now it's a CMD3 response.
                        sim_respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        sim_respLen=48;
                    end
                    
                    ACMD41: begin
                        if ($urandom % 2) begin
                            $display("[SD CARD] ACMD41: card busy");
                            sim_respOut=136'h3f00ff8080ffffffffffffffffffffffff;
                        end
                        else begin
                            $display("[SD CARD] ACMD41: card ready");
                            sim_respOut=136'h3fc1ff8080ffffffffffffffffffffffff;
                        end
                        sim_respLen=48;
                    end
                    
                    default: begin
                        $display("[SD CARD] BAD COMMAND: CMD%0d", sim_cmdIn_cmdIndex);
                        `finish;
                    end
                    endcase
                    
                    // Signal busy (DAT=0) if we were previously writing,
                    // and we received the stop command
                    signalBusy = (sim_cmdIn_cmdIndex===12 && sim_recvWriteData);
                    if (signalBusy) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        sim_datOut[0] = 0;
                    end
                    
                    // Wait a random number of clocks before providing response
                    count = ($urandom%10)+1;
                    $display("[SD CARD] Response: delaying %0d clocks", count);
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    // sim_respOut = {2'b00, 6'b0, 32'b0, 7'b0, 1'b1};
                    $display("[SD CARD] Sending response: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                        sim_respOut,
                        sim_respOut[135 : 134], // preamble
                        sim_respOut[133 : 128], // cmd
                        sim_respOut[127 :  96], // arg
                        sim_respOut[95  :  89], // crc
                        sim_respOut[88],        // end bit
                    );
                    
                    for (i=0; i<sim_respLen; i++) begin
                        wait(!sd_clk);
                        sim_cmdOut = sim_respOut[135];
                        sim_respOut = sim_respOut<<1;
                        wait(sd_clk);
                    end
                end
                wait(!sd_clk);
                sim_cmdOut = 1'bz;
                
                case (sim_cmd)
                CMD11: begin
                    // Drive CMD/DAT lines low
                    sim_cmdOut = 0;
                    sim_datOut = 0;
                    // Wait 5ms
                    #(5*1000000);
                    // Let go of CMD line
                    sim_cmdOut = 1'bz;
                    // Wait 1ms
                    #(1*1000000);
                    // Let go of DAT lines
                    sim_datOut = 4'bzzzz;
                end
                
                CMD12: begin
                    sim_recvWriteData = 0;
                    sim_sendReadData = 0;
                end
                
                CMD18: begin
                    sim_sendReadData = 1;
                end
                
                CMD25: begin
                    sim_recvWriteData = 1;
                end
                endcase
                
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
                
                // Note whether the next command is an application-specific command
                sim_acmd = (sim_cmdIn_cmdIndex==55);
            end
            wait(!sd_clk);
        end
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
                
                sim_dat_crcRst_ = 1;
                
                for (i=0; i<1024 && sim_recvWriteData; i++) begin
                    wait(sd_clk);
                    sim_payloadDataReg = (sim_payloadDataReg<<4)|sd_dat[3:0];
                    wait(!sd_clk);
                end
                
                if (sim_recvWriteData) begin
                    $display("[SD CARD] Received write data: %h", sim_payloadDataReg);
                end
                
                if (sim_recvWriteData) begin
                    sim_dat_ourCRCReg[3] = sim_dat_crc[3];
                    sim_dat_ourCRCReg[2] = sim_dat_crc[2];
                    sim_dat_ourCRCReg[1] = sim_dat_crc[1];
                    sim_dat_ourCRCReg[0] = sim_dat_crc[0];
                    sim_dat_crcRst_ = 0;
                end
                
                for (i=0; i<16 && sim_recvWriteData; i++) begin
                    wait(sd_clk);
                    sim_dat_theirCRCReg[3] = (sim_dat_theirCRCReg[3]<<1)|sd_dat[3];
                    sim_dat_theirCRCReg[2] = (sim_dat_theirCRCReg[2]<<1)|sd_dat[2];
                    sim_dat_theirCRCReg[1] = (sim_dat_theirCRCReg[1]<<1)|sd_dat[1];
                    sim_dat_theirCRCReg[0] = (sim_dat_theirCRCReg[0]<<1)|sd_dat[0];
                    wait(!sd_clk);
                end
                
                // Check CRCs
                if (sim_recvWriteData) begin
                    if (sim_dat_ourCRCReg[3] !== sim_dat_theirCRCReg[3]) begin
                        $display("[SD CARD] DAT3: Bad CRC (ours=%h, theirs=%h) ❌", sim_dat_ourCRCReg[3], sim_dat_theirCRCReg[3]);
                    end else begin
                        $display("[SD CARD] DAT3: CRC Valid (ours=%h, theirs=%h) ✅", sim_dat_ourCRCReg[3], sim_dat_theirCRCReg[3]);
                    end
                    
                    if (sim_dat_ourCRCReg[2] !== sim_dat_theirCRCReg[2]) begin
                        $display("[SD CARD] DAT2: Bad CRC (ours=%h, theirs=%h) ❌", sim_dat_ourCRCReg[2], sim_dat_theirCRCReg[2]);
                    end else begin
                        $display("[SD CARD] DAT2: CRC Valid (ours=%h, theirs=%h) ✅", sim_dat_ourCRCReg[2], sim_dat_theirCRCReg[2]);
                    end
                    
                    if (sim_dat_ourCRCReg[1] !== sim_dat_theirCRCReg[1]) begin
                        $display("[SD CARD] DAT1: Bad CRC (ours=%h, theirs=%h) ❌", sim_dat_ourCRCReg[1], sim_dat_theirCRCReg[1]);
                    end else begin
                        $display("[SD CARD] DAT1: CRC Valid (ours=%h, theirs=%h) ✅", sim_dat_ourCRCReg[1], sim_dat_theirCRCReg[1]);
                    end
                    
                    if (sim_dat_ourCRCReg[0] !== sim_dat_theirCRCReg[0]) begin
                        $display("[SD CARD] DAT0: Bad CRC (ours=%h, theirs=%h) ❌", sim_dat_ourCRCReg[0], sim_dat_theirCRCReg[0]);
                    end else begin
                        $display("[SD CARD] DAT0: CRC Valid (ours=%h, theirs=%h) ✅", sim_dat_ourCRCReg[0], sim_dat_theirCRCReg[0]);
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
                
                sim_dat_crcRst_ = 0;
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
                reg[15:0] ii;
                reg[7:0] datOutReg;
                
                // Start bit
                wait(!sd_clk);
                sim_datOut = 4'b0000;
                wait(sd_clk);
                
                wait(!sd_clk);
                sim_dat_crcRst_ = 1;

                // // Shift out data
                // sim_payloadDataReg = PAYLOAD_DATA;
                // $display("[SD CARD] Sending read data: %h", sim_payloadDataReg);
                //
                // for (i=0; i<1024 && sim_sendReadData; i++) begin
                //     wait(!sd_clk);
                //     sim_datOut = sim_payloadDataReg[4095:4092];
                //     sim_payloadDataReg = sim_payloadDataReg<<4;
                //     wait(sd_clk);
                // end
                
                // Shift out data
                $display("[SD CARD] Sending read data");
                
                for (i=0; i<128 && sim_sendReadData; i++) begin
                    datOutReg = i;
                    for (ii=0; ii<8 && sim_sendReadData; ii++) begin
                        // $display("[SD CARD] Sending bit: %b", sim_datOut);
                        wait(!sd_clk);
                        sim_datOut = {4{datOutReg[7]}};
                        wait(sd_clk);
                        
                        datOutReg = datOutReg<<1;
                    end
                end
                
                if (sim_sendReadData) begin
                    // sim_dat_ourCRCReg[3] = 16'b1010_1010_1010_XXXX;
                    // sim_dat_ourCRCReg[2] = 16'b1010_1010_1010_XXXX;
                    // sim_dat_ourCRCReg[1] = 16'b1010_1010_1010_XXXX;
                    // sim_dat_ourCRCReg[0] = 16'b1010_1010_1010_XXXX;
                    
                    sim_dat_ourCRCReg[3] = sim_dat_crcNext[3];
                    sim_dat_ourCRCReg[2] = sim_dat_crcNext[2];
                    sim_dat_ourCRCReg[1] = sim_dat_crcNext[1];
                    sim_dat_ourCRCReg[0] = sim_dat_crcNext[0];
                    
                    $display("[SD CARD] CRC3: %h", sim_dat_ourCRCReg[3]);
                    $display("[SD CARD] CRC2: %h", sim_dat_ourCRCReg[2]);
                    $display("[SD CARD] CRC1: %h", sim_dat_ourCRCReg[1]);
                    $display("[SD CARD] CRC0: %h", sim_dat_ourCRCReg[0]);
                    
                    // Shift out CRC
                    for (i=0; i<16 && sim_sendReadData; i++) begin
                        wait(!sd_clk);
                        sim_datOut = {sim_dat_ourCRCReg[3][15], sim_dat_ourCRCReg[2][15], sim_dat_ourCRCReg[1][15], sim_dat_ourCRCReg[0][15]};
                        
                        sim_dat_ourCRCReg[3] = sim_dat_ourCRCReg[3]<<1;
                        sim_dat_ourCRCReg[2] = sim_dat_ourCRCReg[2]<<1;
                        sim_dat_ourCRCReg[1] = sim_dat_ourCRCReg[1]<<1;
                        sim_dat_ourCRCReg[0] = sim_dat_ourCRCReg[0]<<1;
                        wait(sd_clk);
                    end
                end
                
                sim_dat_crcRst_ = 0;
                
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
endmodule
