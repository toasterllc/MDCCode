module SDCardSim(
    input wire      sd_clk,
    inout wire      sd_cmd,
    inout wire[3:0] sd_dat
);
    // ====================
    // SD card emulator
    //   Receive commands, issue responses
    // ====================
    reg[47:0] cmdIn = 0;
    reg[1:0] cmdIn_preamble = 0;
    reg[5:0] cmdIn_cmdIndex = 0;
    reg[31:0] cmdIn_arg = 0;
    reg[6:0] cmdIn_theirCRC = 0;
    reg[0:0] cmdIn_endBit = 0;
    reg[15:0] cmdIn_rca = 0;
    reg[135:0] respOut = 0;
    reg[7:0] respLen = 0;
    
    reg[15:0] rca = 16'h0000;
    
    reg cmdOut = 1'bz;
    assign sd_cmd = cmdOut;
    
    reg acmd = 0;
    wire[6:0] cmd = {acmd, cmdIn_cmdIndex};
    
    localparam PAYLOAD_DATA = {4096{1'b0}};
    // localparam PAYLOAD_DATA = {4096{1'b1}};
    // localparam PAYLOAD_DATA = {128{32'h42434445}};
    // localparam PAYLOAD_DATA = {128{32'hFF00FF00}};
    reg[3:0] datOut = 4'bzzzz;
    reg[4095:0] payloadDataReg = 0;
    assign sd_dat = datOut;
    
    reg recvWriteData = 0;
    reg sendReadData = 0;
    
    
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
        cmdIn <= (cmdIn<<1)|sd_cmd;
    end
    
    
    
    
    
    // ====================
    // CRC (CMD)
    // ====================
    reg cmdIn_ourCRC_rst_ = 0;
    wire[6:0] cmdIn_ourCRC;
    reg[6:0] cmdIn_ourCRCReg = 0;
    CRC7 CRC7_cmdIn(
        .clk(sd_clk),
        .rst_(cmdIn_ourCRC_rst_),
        .din(cmdIn[0]),
        .dout(cmdIn_ourCRC),
        .doutNext()
    );
    
    
    
    
    // ====================
    // CRC (DAT[3:0])
    // ====================
    reg dat_crcRst_ = 0;
    wire[15:0] dat_crc[3:0];
    wire[15:0] dat_crcNext[3:0];
    reg[15:0] dat_ourCRCReg[3:0];
    reg[15:0] dat_theirCRCReg[3:0];
    genvar geni;
    for (geni=0; geni<4; geni=geni+1) begin
        CRC16 crc16(
            .clk(sd_clk),
            .rst_(dat_crcRst_),
            .din(sd_dat[geni]),
            .dout(dat_crc[geni]),
            .doutNext(dat_crcNext[geni])
        );
    end
    
    
    
    
    
    initial begin
        reg halla;
        halla = 0;
        
        forever begin
            cmdIn_ourCRC_rst_ = 0;
            
            wait(sd_clk);
            if (!sd_cmd) begin
                // Receive command
                reg[10:0] i;
                reg[10:0] count;
                reg signalBusy;
                
                wait(!sd_clk);
                signalBusy = 0;
                
                // Start calculating CRC for incoming command
                cmdIn_ourCRC_rst_ = 1;
                
                for (i=0; i<47; i++) begin
                    wait(sd_clk);
                    wait(!sd_clk);
                    if (i == 39) begin
                        cmdIn_ourCRCReg = cmdIn_ourCRC;
                        cmdIn_ourCRC_rst_ = 0;
                    end
                end
                
                // Remember our command index/argument/RCA
                cmdIn_preamble = cmdIn[47:46];
                cmdIn_cmdIndex = cmdIn[45:40];
                cmdIn_arg = cmdIn[39:8];
                cmdIn_theirCRC = cmdIn[7:1];
                cmdIn_rca = cmdIn_arg[31:16];
                cmdIn_endBit = cmdIn[0];
                
                $display("[SD CARD] Received command: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                    cmdIn,
                    cmdIn_preamble,     // preamble
                    cmdIn_cmdIndex,     // cmd
                    cmdIn_arg,          // arg
                    cmdIn_theirCRC,     // crc
                    cmdIn_endBit,       // end bit
                );
                
                if (cmdIn_preamble !== 2'b01) begin
                    $display("[SD CARD] Bad preamble: %b ❌", cmdIn_preamble);
                    `finish;
                end
                
                if (cmdIn_theirCRC === cmdIn_ourCRCReg) begin
                    $display("[SD CARD] ^^^ CRC Valid ✅");
                end else begin
                    $display("[SD CARD] ^^^ Bad CRC: ours=%b, theirs=%b ❌", cmdIn_ourCRCReg, cmdIn[7:1]);
                    `finish;
                end
                
                if (cmdIn_endBit !== 1'b1) begin
                    $display("[SD CARD] Bad end bit: %b ❌", cmdIn_endBit);
                    `finish;
                end
                
                // Issue response if needed
                if (cmdIn_cmdIndex) begin
                    case (cmd)
                    
                    CMD2: begin
                        respOut=136'h3f0353445352313238808bb79d66014677;
                        respLen=136;
                    end
                    
                    CMD3: begin
                        rca = 16'hAAAA;
                        respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD6: begin
                        respOut=136'h0600000900ddffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD7: begin
                        if (cmdIn_rca !== rca) begin
                            $display("[SD CARD] CMD7: Bad RCA received: %h ❌", cmdIn_rca);
                            `finish;
                        end
                        respOut=136'h070000070075ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD8: begin
                        respOut=136'h08000001aa13ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD11: begin
                        respOut=136'h0B0000070081ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD12: begin
                        // TODO: make this a real CMD12 response. right now it's a CMD3 response.
                        respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD18: begin
                        // TODO: make this a real CMD18 response. right now it's a CMD3 response.
                        respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD25: begin
                        // TODO: make this a real CMD18 response. right now it's a CMD3 response.
                        respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    CMD55: begin
                        // TODO: uncomment -- we need this check, but disabled it for the case where we don't do the initialization sequence (because we assume the SD card was already initialized)
                        // if (cmdIn_rca !== rca) begin
                        //     $display("[SD CARD] CMD55: Bad RCA received: %h ❌", cmdIn_rca);
                        //     `finish;
                        // end
                        respOut=136'h370000012083ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    ACMD6: begin
                        respOut=136'h0600000920b9ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    ACMD23: begin
                        if (!cmdIn_arg[22:0]) begin
                            $display("[SD CARD] ACMD23: Zero block count received ❌");
                            `finish;
                        end
                        // TODO: make this a real ACMD23 response. right now it's a CMD3 response.
                        respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                        respLen=48;
                    end
                    
                    ACMD41: begin
                        if ($urandom % 2) begin
                            $display("[SD CARD] ACMD41: card busy");
                            respOut=136'h3f00ff8080ffffffffffffffffffffffff;
                        end
                        else begin
                            $display("[SD CARD] ACMD41: card ready");
                            respOut=136'h3fc1ff8080ffffffffffffffffffffffff;
                        end
                        respLen=48;
                    end
                    
                    default: begin
                        $display("[SD CARD] BAD COMMAND: CMD%0d", cmdIn_cmdIndex);
                        `finish;
                    end
                    endcase
                    
                    // Signal busy (DAT=0) if we were previously writing,
                    // and we received the stop command
                    signalBusy = (cmd===CMD12 && recvWriteData);
                    if (signalBusy) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        datOut[0] = 0;
                    end
                    
                    // Wait a random number of clocks before providing response
                    count = ($urandom%10)+1;
                    $display("[SD CARD] Response: delaying %0d clocks", count);
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    // respOut = {2'b00, 6'b0, 32'b0, 7'b0, 1'b1};
                    $display("[SD CARD] Sending response: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                        respOut,
                        respOut[135 : 134], // preamble
                        respOut[133 : 128], // cmd
                        respOut[127 :  96], // arg
                        respOut[95  :  89], // crc
                        respOut[88],        // end bit
                    );
                    
                    count = ($urandom%respLen);
                    for (i=0; i<respLen; i++) begin
                        wait(!sd_clk);
                        cmdOut = respOut[135];
                        respOut = respOut<<1;
                        
                        // Start sending the data on the DAT lines after a random number of cycles
                        if (cmd===CMD18 && i===count) begin
                            sendReadData = 1;
                        end
                        
                        wait(sd_clk);
                    end
                end
                wait(!sd_clk);
                cmdOut = 1'bz;
                
                case (cmd)
                CMD6: begin
                    reg[511:0] datOutReg;
                    
                    datOutReg = 512'h00000000_00000000_00000000_00000000_03000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000;
                    
                    // Start bit
                    datOut = 4'b0000;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    // Payload
                    for (i=0; i<128; i++) begin
                        datOut = datOutReg[511:508];
                        wait(sd_clk);
                        wait(!sd_clk);
                        datOutReg = datOutReg<<4;
                    end
                    
                    // CRC
                    for (i=0; i<16; i++) begin
                        datOut = 4'b0000;
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    // End bit
                    datOut = 4'b1111;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    // Let go of DAT lines
                    datOut = 4'bzzzz;
                    wait(sd_clk);
                    wait(!sd_clk);
                end
                
                CMD11: begin
                    // Drive CMD/DAT lines low
                    cmdOut = 0;
                    datOut = 0;
                    // Wait 5ms
                    #(5*1000000);
                    // Let go of CMD line
                    cmdOut = 1'bz;
                    // Wait 1ms
                    #(1*1000000);
                    // Let go of DAT lines
                    datOut = 4'bzzzz;
                end
                
                CMD12: begin
                    recvWriteData = 0;
                    sendReadData = 0;
                end
                
                CMD18: begin
                    // sendReadData=1 should have occurred above
                    `assert(sendReadData);
                end
                
                CMD25: begin
                    recvWriteData = 1;
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
                    
                    datOut[0] = 1'bz;
                end
                
                // Note whether the next command is an application-specific command
                acmd = (cmdIn_cmdIndex==55);
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
            if (recvWriteData) begin
                reg[15:0] i;
                reg[7:0] count;
                
                // Wait for start bit
                while (sd_dat[0] && recvWriteData) begin
                    wait(!sd_clk);
                    wait(sd_clk);
                end
                wait(!sd_clk);
                
                dat_crcRst_ = 1;
                
                for (i=0; i<1024 && recvWriteData; i++) begin
                    wait(sd_clk);
                    payloadDataReg = (payloadDataReg<<4)|sd_dat[3:0];
                    wait(!sd_clk);
                end
                
                if (recvWriteData) begin
                    $display("[SD CARD] Received write data: %h", payloadDataReg);
                end
                
                if (recvWriteData) begin
                    dat_ourCRCReg[3] = dat_crc[3];
                    dat_ourCRCReg[2] = dat_crc[2];
                    dat_ourCRCReg[1] = dat_crc[1];
                    dat_ourCRCReg[0] = dat_crc[0];
                    dat_crcRst_ = 0;
                end
                
                for (i=0; i<16 && recvWriteData; i++) begin
                    wait(sd_clk);
                    dat_theirCRCReg[3] = (dat_theirCRCReg[3]<<1)|sd_dat[3];
                    dat_theirCRCReg[2] = (dat_theirCRCReg[2]<<1)|sd_dat[2];
                    dat_theirCRCReg[1] = (dat_theirCRCReg[1]<<1)|sd_dat[1];
                    dat_theirCRCReg[0] = (dat_theirCRCReg[0]<<1)|sd_dat[0];
                    wait(!sd_clk);
                end
                
                // Check CRCs
                if (recvWriteData) begin
                    if (dat_ourCRCReg[3] !== dat_theirCRCReg[3]) begin
                        $display("[SD CARD] DAT3: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[3], dat_theirCRCReg[3]);
                    end else begin
                        $display("[SD CARD] DAT3: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[3], dat_theirCRCReg[3]);
                    end
                    
                    if (dat_ourCRCReg[2] !== dat_theirCRCReg[2]) begin
                        $display("[SD CARD] DAT2: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[2], dat_theirCRCReg[2]);
                    end else begin
                        $display("[SD CARD] DAT2: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[2], dat_theirCRCReg[2]);
                    end
                    
                    if (dat_ourCRCReg[1] !== dat_theirCRCReg[1]) begin
                        $display("[SD CARD] DAT1: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[1], dat_theirCRCReg[1]);
                    end else begin
                        $display("[SD CARD] DAT1: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[1], dat_theirCRCReg[1]);
                    end
                    
                    if (dat_ourCRCReg[0] !== dat_theirCRCReg[0]) begin
                        $display("[SD CARD] DAT0: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[0], dat_theirCRCReg[0]);
                    end else begin
                        $display("[SD CARD] DAT0: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[0], dat_theirCRCReg[0]);
                    end
                end
                
                // Check end bits
                if (recvWriteData) begin
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
                if (recvWriteData) begin
                    // Wait 2 cycles before sending CRC status
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    datOut = 4'b0000;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    datOut = 4'b0000;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    datOut = 4'b0001;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    datOut = 4'b0000;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    datOut = 4'b0001;
                    wait(sd_clk);
                    wait(!sd_clk);
                    
                    // Send busy signal for a random number of cycles
                    count = $urandom%10;
                    if (count) begin
                        // Start bit
                        datOut = 4'b0000;
                        wait(sd_clk);
                        wait(!sd_clk);
                        
                        for (i=0; i<count; i++) begin
                            wait(sd_clk);
                            wait(!sd_clk);
                        end
                        
                        // End bit
                        datOut = 4'b0001;
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    datOut = 4'bzzzz;
                end
                
                dat_crcRst_ = 0;
            end

            wait(!sd_clk);
        end
    end
    
    
    
    
    
    // ====================
    // Handle reading from the card
    // ====================
    initial begin
        forever begin
            wait(sd_clk);
            if (sendReadData) begin
                reg[15:0] i;
                reg[15:0] ii;
                reg[7:0] datOutReg;
                
                // Start bit
                wait(!sd_clk);
                datOut = 4'b0000;
                wait(sd_clk);
                
                wait(!sd_clk);
                dat_crcRst_ = 1;

                // // Shift out data
                // payloadDataReg = PAYLOAD_DATA;
                // $display("[SD CARD] Sending read data: %h", payloadDataReg);
                //
                // for (i=0; i<1024 && sendReadData; i++) begin
                //     wait(!sd_clk);
                //     datOut = payloadDataReg[4095:4092];
                //     payloadDataReg = payloadDataReg<<4;
                //     wait(sd_clk);
                // end
                
                // Shift out data
                $display("[SD CARD] Sending read data");
                
                for (i=0; i<128 && sendReadData; i++) begin
                    datOutReg = i;
                    for (ii=0; ii<8 && sendReadData; ii++) begin
                        // $display("[SD CARD] Sending bit: %b", datOut);
                        wait(!sd_clk);
                        datOut = {4{datOutReg[7]}};
                        wait(sd_clk);
                        
                        datOutReg = datOutReg<<1;
                    end
                end
                
                if (sendReadData) begin
                    // dat_ourCRCReg[3] = 16'b1010_1010_1010_XXXX;
                    // dat_ourCRCReg[2] = 16'b1010_1010_1010_XXXX;
                    // dat_ourCRCReg[1] = 16'b1010_1010_1010_XXXX;
                    // dat_ourCRCReg[0] = 16'b1010_1010_1010_XXXX;
                    
                    dat_ourCRCReg[3] = dat_crcNext[3];
                    dat_ourCRCReg[2] = dat_crcNext[2];
                    dat_ourCRCReg[1] = dat_crcNext[1];
                    dat_ourCRCReg[0] = dat_crcNext[0];
                    
                    $display("[SD CARD] CRC3: %h", dat_ourCRCReg[3]);
                    $display("[SD CARD] CRC2: %h", dat_ourCRCReg[2]);
                    $display("[SD CARD] CRC1: %h", dat_ourCRCReg[1]);
                    $display("[SD CARD] CRC0: %h", dat_ourCRCReg[0]);
                    
                    // Shift out CRC
                    for (i=0; i<16 && sendReadData; i++) begin
                        wait(!sd_clk);
                        datOut = {dat_ourCRCReg[3][15], dat_ourCRCReg[2][15], dat_ourCRCReg[1][15], dat_ourCRCReg[0][15]};
                        
                        dat_ourCRCReg[3] = dat_ourCRCReg[3]<<1;
                        dat_ourCRCReg[2] = dat_ourCRCReg[2]<<1;
                        dat_ourCRCReg[1] = dat_ourCRCReg[1]<<1;
                        dat_ourCRCReg[0] = dat_ourCRCReg[0]<<1;
                        wait(sd_clk);
                    end
                end
                
                dat_crcRst_ = 0;
                
                // End bit
                wait(!sd_clk);
                datOut = 4'b1111;
                wait(sd_clk);
                
                // Stop driving DAT lines
                wait(!sd_clk);
                datOut = 4'bzzzz;
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
