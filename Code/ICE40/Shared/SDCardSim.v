`ifndef SDCardSim_v
`define SDCardSim_v

`include "EndianSwap.v"
`include "PixelValidator.v"

`timescale 1ps/1ps

module Sim_CRC7(
    input wire clk,
    input wire rst_,
    input din,
    output wire[6:0] dout,
    output wire[6:0] doutNext
);
    reg[6:0] d = 0;
    wire dx = din ^ d[6];
    wire[6:0] dnext = { d[5], d[4], d[3], d[2]^dx, d[1], d[0], dx };
    always @(posedge clk)
        if (!rst_) d <= 0;
        else d <= dnext;
    assign dout = d;
    assign doutNext = dnext;
endmodule


module Sim_CRC16(
    input wire clk,
    input wire rst_,
    input din,
    output wire[15:0] dout,
    output wire[15:0] doutNext
);
    reg[15:0] d = 0;
    wire dx = din^d[15];
    wire[15:0] dnext = { d[14], d[13], d[12], d[11]^dx, d[10], d[9], d[8], d[7], d[6], d[5], d[4]^dx, d[3], d[2], d[1], d[0], dx };
    always @(posedge clk)
        if (!rst_) d <= 0;
        else d <= dnext;
    assign dout = d;
    assign doutNext = dnext;
endmodule






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
    
    reg[3:0] datOut = 4'bzzzz;
    assign sd_dat = datOut;
    
    reg recvWriteData = 0;
    reg sendReadData = 0;
    reg sendCMD6Data = 0;
    
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
    Sim_CRC7 Sim_CRC7(
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
        Sim_CRC16 Sim_CRC16(
            .clk(sd_clk),
            .rst_(dat_crcRst_),
            .din(sd_dat[geni]),
            .dout(dat_crc[geni]),
            .doutNext(dat_crcNext[geni])
        );
    end
    
    
    
    
    
    // ====================
    // Handle commands from the host
    // ====================
    localparam Duration5Ms = 5_000_000_000;
    initial begin
        reg lvsinit_sdCmd;
        reg[3:0] lvsinit_sdDat;
        time lvsinit_pulseBeginTimePs;
        time lvsinit_pulseEndTimePs;
        
        // Handle LVS init sequence
        $display("[SDCardSim] Waiting for LVS init sequence...");
        wait(sd_clk);
        lvsinit_pulseBeginTimePs = $time;
        lvsinit_sdCmd = sd_cmd;
        lvsinit_sdDat = sd_dat;
        wait(!sd_clk);
        lvsinit_pulseEndTimePs = $time;
        
        if (lvsinit_sdCmd===1'b0 && lvsinit_sdDat===4'b0 && (lvsinit_pulseEndTimePs-lvsinit_pulseBeginTimePs)>10000000) begin
            $display("[SDCardSim] LVS init succeeded [ sd_cmd: %b, sd_dat: %b, pulse duration (ns): %0d ] ✅",
                lvsinit_sdCmd,
                lvsinit_sdDat,
                (lvsinit_pulseEndTimePs-lvsinit_pulseBeginTimePs)/1000
            );
        end else begin
            $display("[SDCardSim] LVS init failed [ sd_cmd: %b, sd_dat: %b, pulse duration (ns): %0d ] ❌",
                lvsinit_sdCmd,
                lvsinit_sdDat,
                (lvsinit_pulseEndTimePs-lvsinit_pulseBeginTimePs)/1000
            );
            `Finish;
        end
        
        // Verify that there's a 5ms delay after the LVS sequence before the first clock is supplied
        wait(sd_clk);
        
        if (($time-lvsinit_pulseEndTimePs) >= Duration5Ms) begin
            $display("[SDCardSim] First sd_clk after LVS init occurred after more than 5ms (elapsed: %0d us) ✅",
                ($time-lvsinit_pulseEndTimePs)/1000000
            );
        end else begin
            `ifdef SIM
                $display("[SDCardSim] First sd_clk after LVS init occurred before 5ms elapsed (elapsed: %0d us); ignoring because SIM is defined",
                    ($time-lvsinit_pulseEndTimePs)/1000000
                );
            `else
                $display("[SDCardSim] First sd_clk after LVS init occurred before 5ms elapsed (elapsed: %0d us) ❌",
                    ($time-lvsinit_pulseEndTimePs)/1000000
                );
                `Finish;
            `endif
        end
        
        forever begin
            cmdIn_ourCRC_rst_ = 0;
            
            wait(sd_clk);
            if (sd_cmd === 1'b0) begin
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
                
                $display("[SDCardSim] Received command: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                    cmdIn,
                    cmdIn_preamble,     // preamble
                    cmdIn_cmdIndex,     // cmd
                    cmdIn_arg,          // arg
                    cmdIn_theirCRC,     // crc
                    cmdIn_endBit,       // end bit
                );
                
                if (cmdIn_preamble !== 2'b01) begin
                    $display("[SDCardSim] Bad preamble (expected:01 got:%b) ❌", cmdIn_preamble);
                    `Finish;
                end
                
                // Use ==, not ===, because we want x's to be considered unequal
                if (cmdIn_theirCRC == cmdIn_ourCRCReg) begin
                    $display("[SDCardSim] ^^^ CRC Valid ✅");
                end else begin
                    $display("[SDCardSim] ^^^ Bad CRC: ours=%b, theirs=%b ❌", cmdIn_ourCRCReg, cmdIn[7:1]);
                    `Finish;
                end
                
                if (cmdIn_endBit !== 1'b1) begin
                    $display("[SDCardSim] Bad end bit: %b ❌", cmdIn_endBit);
                    // `Finish;
                end
                
                // Issue response if needed
                case (cmd)
                CMD0: begin
                    respLen=0;
                end
                
                CMD2: begin
                    // respOut = 136'h3f_f353445352313238808bb79d660146_01;
                    // respOut = 136'h3f_fffe0032db790003b8ab7f800a4041_e3;
                    
                    // respOut = 136'h3f_7ffe0032db790003b8ab7f800a4041_6b;
                    
                    // respOut = 136'h3f_7ffe0032db790003b8ab7f800a4040_79; // good
                    // respOut = 136'h3f_7ffe0032db790003b8ab7f800a4040_x9; // incorrectly affects SDController's calculated crc
                    
                    // respOut = 136'h3f_fffe0032db790003b8ab7f800a4040_f1;
                    
                    respOut=136'h3f_0353445352313238808bb79d660146_77; // Real CMD2 response
                    // respOut=136'h3f_400e0032db790003b8ab7f800a4040_5f; // Alternative R2 response (actually a CMD9 response)
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
                        $display("[SDCardSim] CMD7: Bad RCA received: %h ❌", cmdIn_rca);
                        `Finish;
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
                    // TODO: make this a real CMD25 response. right now it's a CMD3 response.
                    respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                    respLen=48;
                end
                
                CMD55: begin
                    // TODO: uncomment -- we need this check, but disabled it for the case where we don't do the initialization sequence (because we assume the SD card was already initialized)
                    // if (cmdIn_rca !== rca) begin
                    //     $display("[SDCardSim] CMD55: Bad RCA received: %h ❌", cmdIn_rca);
                    //     `Finish;
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
                        $display("[SDCardSim] ACMD23: Zero block count received ❌");
                        `Finish;
                    end
                    // TODO: make this a real ACMD23 response. right now it's a CMD3 response.
                    respOut=136'h03aaaa0520d1ffffffffffffffffffffff;
                    respLen=48;
                end
                
                ACMD41: begin
                    if ($urandom % 2) begin
                        $display("[SDCardSim] ACMD41: card busy");
                        respOut=136'h3f00ff8080ffffffffffffffffffffffff;
                    end
                    else begin
                        $display("[SDCardSim] ACMD41: card ready");
                        respOut=136'h3fc1ff8080ffffffffffffffffffffffff;
                    end
                    respLen=48;
                end
                
                default: begin
                    $display("[SDCardSim] BAD COMMAND: CMD%0d (%b)", cmdIn_cmdIndex, cmd);
                    `Finish;
                end
                endcase
                
                // Handle stop command (CMD12)
                // This needs to happen before we send the response, because the dataflow is supposed
                // to stop N_SD=[2,3] cycles after the end of CMD12
                if (cmd === CMD12) begin
                    recvWriteData = 0;
                    sendReadData = 0;
                end
                
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
                
                if (respLen) begin
                    // Wait a 0-64 clocks before providing response
                    // (See the NCR timing parameter in the SD spec)
                    count = ($urandom%65);
                    $display("[SDCardSim] Response: delaying %0d clocks", count);
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    // respOut = {2'b00, 6'b0, 32'b0, 7'b0, 1'b1};
                    if (respLen === 48) begin
                        $display("[SDCardSim] Sending response: %b [ preamble: %b, cmd: %0d, arg: %x, crc: %b, end: %b ]",
                            respOut,
                            respOut[135 : 134], // preamble
                            respOut[133 : 128], // cmd
                            respOut[127 :  96], // arg
                            respOut[95  :  89], // crc
                            respOut[88],        // end bit
                        );
                    
                    end else if (respLen === 136) begin
                        $display("[SDCardSim] Sending response: %b [ preamble: %b, cmd: %0d, crc: %b, end: %b ]",
                            respOut,
                            respOut[135 : 134], // preamble
                            respOut[133 : 128], // cmd
                            respOut[7   :  1],  // crc
                            respOut[0],         // end bit
                        );
                    end
                    
                    count = ($urandom%respLen);
                    for (i=0; i<respLen; i++) begin
                        wait(!sd_clk);
                        cmdOut = respOut[135];
                        respOut = respOut<<1;
                        
                        // Start sending data on the DAT lines after a random number of cycles
                        if (i === count) begin
                            case (cmd)
                            CMD6:   sendCMD6Data = 1;
                            CMD18:  sendReadData = 1;
                            endcase
                        end
                        
                        wait(sd_clk);
                    end
                end
                
                
                
                
                
                
                
                
                wait(!sd_clk);
                cmdOut = 1'bz;
                
                case (cmd)
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
                
                CMD18: begin
                    // sendReadData=1 should have occurred above
                    `Assert(sendReadData);
                end
                
                CMD25: begin
                    recvWriteData = 1;
                end
                endcase
                
                // Stop signaling busy, if we were signaling busy
                if (signalBusy) begin
                    // Wait a random number of clocks before de-asserting busy
                    count = $urandom%16;
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end

                    // Drive 1
                    datOut[0] = 1'b1;

                    wait(sd_clk);
                    wait(!sd_clk);

                    // Let go
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
    PixelValidator PixelValidator();
    
    initial begin
        forever begin
            wait(sd_clk);
            if (recvWriteData) begin
                reg[4095:0] datInReg;
                reg[31:0] i;
                reg[7:0] count;
                reg crcOK;
                
                // Wait for start bit
                while (sd_dat[0]!==1'b0 && recvWriteData) begin
                    wait(!sd_clk);
                    wait(sd_clk);
                end
                
                if (recvWriteData) begin
                    if (sd_dat[0] === 1'b0) begin
                        $display("[SDCardSim] Good start bit ✅");
                    end else begin
                        $display("[SDCardSim] Bad start bit ❌: %b", sd_dat[0]);
                    end
                end
                
                wait(!sd_clk);
                
                dat_crcRst_ = 1;
                
                for (i=0; i<1024 && recvWriteData; i++) begin
                    wait(sd_clk);
                    datInReg = (datInReg<<4)|sd_dat[3:0];
                    wait(!sd_clk);
                    
                    // Validate every 16-bit word
                    if (i[1:0] === 3) begin
                        PixelValidator.Validate(datInReg[15:0]);
                    end
                end
                
                if (recvWriteData) begin
                    $display("[SDCardSim] Received write data: %h", datInReg);
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
                crcOK = 1;
                if (recvWriteData) begin
                    // Use ==, not ===, because we want x's to be considered unequal
                    if (dat_ourCRCReg[3] == dat_theirCRCReg[3]) begin
                        $display("[SDCardSim] DAT3: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[3], dat_theirCRCReg[3]);
                    end else begin
                        $display("[SDCardSim] DAT3: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[3], dat_theirCRCReg[3]);
                        crcOK = 0;
                    end
                    
                    if (dat_ourCRCReg[2] == dat_theirCRCReg[2]) begin
                        $display("[SDCardSim] DAT2: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[2], dat_theirCRCReg[2]);
                    end else begin
                        $display("[SDCardSim] DAT2: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[2], dat_theirCRCReg[2]);
                        crcOK = 0;
                    end
                    
                    if (dat_ourCRCReg[1] == dat_theirCRCReg[1]) begin
                        $display("[SDCardSim] DAT1: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[1], dat_theirCRCReg[1]);
                    end else begin
                        $display("[SDCardSim] DAT1: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[1], dat_theirCRCReg[1]);
                        crcOK = 0;
                    end
                    
                    if (dat_ourCRCReg[0] == dat_theirCRCReg[0]) begin
                        $display("[SDCardSim] DAT0: CRC Valid (ours=%h, theirs=%h) ✅", dat_ourCRCReg[0], dat_theirCRCReg[0]);
                    end else begin
                        $display("[SDCardSim] DAT0: Bad CRC (ours=%h, theirs=%h) ❌", dat_ourCRCReg[0], dat_theirCRCReg[0]);
                        crcOK = 0;
                    end
                end
                
                // Check end bits
                if (recvWriteData) begin
                    wait(sd_clk);
                    if (sd_dat[3] === 1'b1) begin
                        $display("[SDCardSim] DAT3: End bit OK ✅");
                    end else begin
                        $display("[SDCardSim] DAT3: Bad end bit: %b ❌", sd_dat[3]);
                        crcOK = 0;
                    end
                    
                    if (sd_dat[2] === 1'b1) begin
                        $display("[SDCardSim] DAT2: End bit OK ✅");
                    end else begin
                        $display("[SDCardSim] DAT2: Bad end bit: %b ❌", sd_dat[2]);
                        crcOK = 0;
                    end
                    
                    if (sd_dat[1] === 1'b1) begin
                        $display("[SDCardSim] DAT1: End bit OK ✅");
                    end else begin
                        $display("[SDCardSim] DAT1: Bad end bit: %b ❌", sd_dat[1]);
                        crcOK = 0;
                    end
                    
                    if (sd_dat[0] === 1'b1) begin
                        $display("[SDCardSim] DAT0: End bit OK ✅");
                    end else begin
                        $display("[SDCardSim] DAT0: Bad end bit: %b ❌", sd_dat[0]);
                        crcOK = 0;
                    end
                    wait(!sd_clk);
                end
                
                // Send CRC status token
                if (recvWriteData) begin
                    
                    // Wait 2-8 cycles before sending CRC status
                    // SD spec:
                    //   NCRC:
                    //     2-8 cycles
                    //     Period between an end bit of write data and a start bit of CRC status."
                    
                    count = 2+($urandom%7);
                    for (i=0; i<count; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    if (crcOK) begin
                        // Positive CRC status
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
                    
                    end else begin
                        // Negative CRC status
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
                        
                        datOut = 4'b0001;
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    // Send busy signal for a random number of cycles
                    count = $urandom%16;
                    if (count) begin
                        datOut = 4'b0000;
                        for (i=0; i<count; i++) begin
                            wait(sd_clk);
                            wait(!sd_clk);
                        end
                    end
                    
                    datOut = 4'b0001;
                    // Output several cycles of a strong 'DAT0=1' before we switch to 'DAT[3:0]=ZZZZ'.
                    // This is so that our simulation still works even if the sd_cmd/sd_dat lines are
                    // defined as 'wire' instead of 'tri1'. By outputting several cycles, we give
                    // SDController a chance to observe our strong 1. (At the time of writing,
                    // SDController takes a few cycles before checking the DAT0 state for busy, so if
                    // we only output one cycle of a strong 1, it'll get missed.)
                    for (i=0; i<4; i++) begin
                        wait(sd_clk);
                        wait(!sd_clk);
                    end
                    
                    datOut = 4'bzzzz;
                end
                
                dat_crcRst_ = 0;
            
            end else begin
                PixelValidator.Reset();
            end
            
            wait(!sd_clk);
        end
    end
    
    
    
    
    
    // ====================
    // Handle reading from the card
    // ====================
    parameter Send_WordWidth        = 16;
    parameter Send_WordIncrement    = -1;
    EndianSwap #(.Width(Send_WordWidth)) Send_EndianSwap();
    
    initial begin
        reg[Send_WordWidth-1:0] nextDatOutVal;
        
        forever begin
            wait(sd_clk);
            if (sendReadData) begin
                reg[15:0] i;
                reg[15:0] ii;
                reg[15:0] count;
                reg[4095:0] datOutReg;
                
                // Start bit
                wait(!sd_clk);
                datOut = 4'b0000;
                wait(sd_clk);
                
                wait(!sd_clk);
                dat_crcRst_ = 1;
                
                // Fill datOutReg with incrementing/decrementing words
                for (i=0; i<$size(datOutReg)/Send_WordWidth; i++) begin
                    datOutReg[$size(datOutReg)-(i*Send_WordWidth)-1 -: Send_WordWidth] = Send_EndianSwap.Swap(nextDatOutVal);
                    nextDatOutVal = nextDatOutVal + Send_WordIncrement;
                end
                
                // // Fill datOutReg with random data
                // for (i=0; i<$size(datOutReg)/32; i++) begin
                //     datOutReg[((32*((i)+1))-1) -: 32] = $urandom;
                // end
                
                // Shift out data
                $display("[SDCardSim:ReadData] Sending read data: %h", datOutReg);
                for (i=0; i<1024 && sendReadData; i++) begin
                    wait(!sd_clk);
                    datOut = datOutReg[4095:4092];
                    datOutReg = datOutReg<<4;
                    wait(sd_clk);
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
                    
                    $display("[SDCardSim:ReadData] CRC3: %h", dat_ourCRCReg[3]);
                    $display("[SDCardSim:ReadData] CRC2: %h", dat_ourCRCReg[2]);
                    $display("[SDCardSim:ReadData] CRC1: %h", dat_ourCRCReg[1]);
                    $display("[SDCardSim:ReadData] CRC0: %h", dat_ourCRCReg[0]);
                    
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
                
                if (sendReadData) begin
                    // End bit
                    wait(!sd_clk);
                    datOut = 4'b1111;
                    wait(sd_clk);
                    
                    // Wait between [8,20] cycles before starting the next block.
                    //
                    // The SD spec specifies exactly N_AC=8 cycles between blocks,
                    // but we want to make sure that SDController is more robust
                    // to a varying number of cycles.
                    count = 8+($urandom%13);
                    $display("[SDCardSim:ReadData] Waiting %0d cycles before outputting next block", count);
                    for (i=0; i<count; i++) begin
                        wait(!sd_clk);
                        wait(sd_clk);
                    end
                
                end else begin
                    // Stop driving DAT lines if we're bailing
                    wait(!sd_clk);
                    datOut = 4'bzzzz;
                    wait(sd_clk);
                end
            
            end else begin
                nextDatOutVal = (Send_WordIncrement>0 ? 0 : '1);
            end
            
            wait(!sd_clk);
        end
    end
    
    
    
    
    
    
    
    
    
    
    // ====================
    // Handle CMD6 DAT output
    // ====================
    reg[3:0] accessMode = 0;
    initial begin
        reg[31:0] nextDatOutVal;
        // nextDatOutVal = 0;
        nextDatOutVal = '1;
        
        forever begin
            wait(sd_clk);
            if (sendCMD6Data) begin
                reg[511:0] datOutReg;
                reg[10:0] i;
                reg changeAccessMode;
                reg[3:0] newAccessMode;
                reg[3:0] respAccessMode;
                
                // Handle new access mode
                changeAccessMode = cmdIn_arg[31];
                if (changeAccessMode) begin
                    $display("[SDCardSim] Change access mode = 1 ✅");
                end else begin
                    $display("[SDCardSim] Change access mode = 0 ❌");
                    `Finish;
                end
                
                newAccessMode = cmdIn_arg[3:0];
                case (newAccessMode)
                // SDR12
                4'h0: begin
                    accessMode = 4'h0;
                    respAccessMode = 4'h0;
                end
                
                // SDR104
                4'h3: begin
                    accessMode = 4'h3;
                    respAccessMode = 4'h3;
                end
                
                // No change
                4'hF: begin
                    respAccessMode = accessMode;
                end
                
                // Error
                default: begin
                    respAccessMode = 4'hF;
                end
                endcase
                
                datOutReg = 0;
                
                // // Fill datOutReg with incrementing u8
                // for (i=0; i<$size(datOutReg)/8; i++) begin
                //     datOutReg[$size(datOutReg)-(i*8)-1 -: 8] = nextDatOutVal;
                //     nextDatOutVal = nextDatOutVal+1;
                // end
                //
                // // Fill datOutReg with decrementing u8
                // for (i=0; i<$size(datOutReg)/8; i++) begin
                //     datOutReg[$size(datOutReg)-(i*8)-1 -: 8] = nextDatOutVal;
                //     nextDatOutVal = nextDatOutVal-1;
                // end
                //
                // // Fill datOutReg with incrementing u16
                // for (i=0; i<$size(datOutReg)/16; i++) begin
                //     datOutReg[$size(datOutReg)-(i*16)-1 -: 16] = nextDatOutVal;
                //     nextDatOutVal = nextDatOutVal+1;
                // end
                //
                // // Fill datOutReg with decrementing u16
                // for (i=0; i<$size(datOutReg)/16; i++) begin
                //     datOutReg[$size(datOutReg)-(i*16)-1 -: 16] = nextDatOutVal;
                //     nextDatOutVal = nextDatOutVal-1;
                // end
                //
                // // Fill datOutReg with incrementing u32
                // for (i=0; i<$size(datOutReg)/32; i++) begin
                //     datOutReg[$size(datOutReg)-(i*32)-1 -: 32] = i;
                //     nextDatOutVal = nextDatOutVal+1;
                // end
                //
                // // Fill datOutReg with decrementing u32
                // for (i=0; i<$size(datOutReg)/32; i++) begin
                //     datOutReg[$size(datOutReg)-(i*32)-1 -: 32] = nextDatOutVal;
                //     nextDatOutVal = nextDatOutVal-1;
                // end
                
                // Fill datOutReg with random data
                for (i=0; i<$size(datOutReg)/32; i++) begin
                    datOutReg[((32*((i)+1))-1) -: 32] = $urandom;
                end
                
                datOutReg[379:376] = respAccessMode;
                
                // Send response
                $display("[SDCardSim] Sending CMD6 response: %h", datOutReg);
                wait(!sd_clk);
                dat_crcRst_ = 1;
                
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
                dat_ourCRCReg[3] = dat_crc[3];
                dat_ourCRCReg[2] = dat_crc[2];
                dat_ourCRCReg[1] = dat_crc[1];
                dat_ourCRCReg[0] = dat_crc[0];
                
                $display("[SDCardSim] CMD6 DatOut CRC3: %h", dat_ourCRCReg[3]);
                $display("[SDCardSim] CMD6 DatOut CRC2: %h", dat_ourCRCReg[2]);
                $display("[SDCardSim] CMD6 DatOut CRC1: %h", dat_ourCRCReg[1]);
                $display("[SDCardSim] CMD6 DatOut CRC0: %h", dat_ourCRCReg[0]);
                
                // Shift out CRC
                for (i=0; i<16; i++) begin
                    datOut = {dat_ourCRCReg[3][15], dat_ourCRCReg[2][15], dat_ourCRCReg[1][15], dat_ourCRCReg[0][15]};
                    // datOut = 4'bxxxx;
                    
                    dat_ourCRCReg[3] = dat_ourCRCReg[3]<<1;
                    dat_ourCRCReg[2] = dat_ourCRCReg[2]<<1;
                    dat_ourCRCReg[1] = dat_ourCRCReg[1]<<1;
                    dat_ourCRCReg[0] = dat_ourCRCReg[0]<<1;
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
                
                sendCMD6Data = 0;
                
                dat_crcRst_ = 0;
            end
            wait(!sd_clk);
        end
    end
endmodule

`endif
