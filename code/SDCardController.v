`include "Util.v"
`include "CRC7.v"
`include "CRC16.v"
`include "ShiftAdder.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

// TODO: we may want to add support for partial reads, so we don't have to read a full block if the client only wants a few bytes

// TODO: for perf, try removing StateCmdOut state (the way we used to have it) so that the calling state sets up the registers.

// TODO: try having states set CMD/ARG registers, instead of the full cmdOutReg

module SDCardController(
    input wire          clk,
    
    // Command port
    input wire          cmd_trigger,
    output reg          cmd_accepted = 0,
    input wire          cmd_write,
    input wire[22:0]    cmd_writeLen,
    input wire[31:0]    cmd_addr,       // (2^32)*512 == 2 TB
    // input wire[13:0]    cmd_len,        // (2^14)*512 == 8 MB max transfer size
    
    // Data-out port
    output reg[15:0]    dataOut = 0,
    output reg          dataOut_valid = 0,
    
    // Data-in port
    input wire[15:0]    dataIn,
    output reg          dataIn_accepted = 0,
    
    // Error port
    output reg          err = 0,
    
    // SDIO port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    // ====================
    // Pin: sd_clk
    // ====================
    assign sd_clk = clk;
    
    
    
    
    // ====================
    // Pin: sd_cmd
    // ====================
    wire sd_cmdIn;
    wire sd_cmdOut = cmdOut;
    wire sd_cmdOutActive = cmdOutActive;
    SB_IO #(
        .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
        .NEG_TRIGGER(1'b1)
    ) sbio (
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_CLK(clk),
        .OUTPUT_ENABLE(sd_cmdOutActive),
        .D_OUT_0(sd_cmdOut),
        .D_IN_0(sd_cmdIn)
    );
    
    
    
    
    // ====================
    // Pin: sd_dat
    // ====================
    wire[3:0] sd_datIn;
    wire[3:0] sd_datOut = datOutReg[19:16];
    wire sd_datOutActive = datOutActive;
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_01),      // Output=PIN_OUTPUT_REGISTERED_ENABLE_REGISTERED, Input=PIN_INPUT
            .NEG_TRIGGER(1'b1)
        ) sbio (
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_CLK(clk),
            .OUTPUT_ENABLE(sd_datOutActive),
            .D_OUT_0(sd_datOut[i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    
    
    
    
    
    
    
    // ====================
    // State Machine Registers
    // ====================
    localparam StateIdle        = 0;    // +0
    localparam StateWrite       = 1;    // +3
    localparam StateRead        = 5;    // +2
    localparam StateCmdOut      = 8;    // +2
    localparam StateStop        = 11;   // +0
    reg[3:0] state = 0;
    reg[3:0] nextState = 0;
    
    localparam RespStateIdle    = 0;    // +0
    localparam RespStateIn      = 1;    // +3
    localparam RespStateDone    = 5;    // +0
    reg[3:0] respState = 0;
    
    localparam DatStateIdle     = 0;    // +0
    localparam DatStateIn       = 1;    // +4
    localparam DatStateDone     = 6;    // +0
    reg[3:0] datState = 0;
    
    localparam CMD0 =   6'd0;       // GO_IDLE_STATE
    localparam CMD12 =  6'd12;      // STOP_TRANSMISSION
    localparam CMD18 =  6'd18;      // READ_MULTIPLE_BLOCK
    localparam CMD25 =  6'd25;      // WRITE_MULTIPLE_BLOCK
    localparam CMD55 =  6'd55;      // APP_CMD
    
    localparam ACMD23 = 6'd23;      // SET_WR_BLK_ERASE_COUNT
    
    reg cmdInStaged = 0;
    reg[47:0] cmdInReg = 0;
    wire cmdIn = sd_cmdIn;
    
    wire[3:0] datIn = sd_datIn;
    reg[15:0] datInReg = 0;
    reg[3:0] datInCounter = 0;
    reg[19:0] datOutReg = 0;
    reg[3:0] datOutCounter = 0;
    reg[9:0] blockCounter = 0;
    reg[47:0] resp = 0;
    reg datOutActive = 0;
    
    reg cmdOutActive = 0;
    reg[47:0] cmdOutReg = 0;
    reg[5:0] cmdOutCmd = 0;
    reg[31:0] cmdOutArg = 0;
    wire cmdOut = cmdOutReg[47];
    reg[5:0] cmdOutCounter = 0;
    reg cmdOutRespWait = 0;
    
    reg[31:0] cmdAddr = 0;
    reg[22:0] cmdWriteLen = 0;
    // reg[13:0] cmdLen = 0;
    // wire[13:0] cmdLenNext = cmdLen-1;
    // ShiftAdder #(
    //     .W(13),
    //     .N(1)
    // ) adder(
    //     .clk(clk),
    //     .a(cmdLen),
    //     .b(-13'd1),
    //     .sum(cmdLenNext)
    // );
    
    
    
    
    // ====================
    // CRC (CMD in)
    // ====================
    wire[6:0] cmdInCRC;
    reg cmdInCRCRst_ = 0;
    CRC7 CRC7_cmdIn(
        .clk(clk),
        .rst_(cmdInCRCRst_),
        .din(cmdInReg[0]),
        .dout(),
        .doutNext(cmdInCRC)
    );
    
    reg[6:0] cmdInCRCReg = 0;
    
    // ====================
    // CRC (CMD out)
    // ====================
    wire[6:0] cmdOutCRC;
    CRC7 CRC7_cmdOut(
        .clk(clk),
        .rst_(cmdOutActive),
        .din(cmdOutReg[47]),
        .dout(),
        .doutNext(cmdOutCRC)
    );
    
    // ====================
    // CRC (DAT[3:0])
    // ====================
    reg datInCRCRst_ = 0;
    wire[15:0] datInCRC[3:0];
    for (i=0; i<4; i=i+1) begin
        CRC16 crc16(
            .clk(clk),
            .rst_(datInCRCRst_),
            .din(datInReg[4+i]),
            .dout(datInCRC[i]),
            .doutNext()
        );
    end
    
    reg[15:0] datIn3CRCReg = 0;
    reg[15:0] datIn2CRCReg = 0;
    reg[15:0] datIn1CRCReg = 0;
    reg[15:0] datIn0CRCReg = 0;
    
    
    
    
    
    // ====================
    // State Machine
    // ====================
    always @(posedge clk) begin
        cmdOutReg <= cmdOutReg<<1;
        cmdOutCounter <= cmdOutCounter-1;
        
        cmdInStaged <= (cmdOutActive ? 1'b1 : cmdIn);
        cmdInReg <= (cmdInReg<<1)|cmdInStaged;
        
        datInReg <= (datInReg<<4)|{datIn[3], datIn[2], datIn[1], datIn[0]};
        datInCounter <= datInCounter-1;
        
        datOutReg <= datOutReg<<4;
        datOutCounter <= datOutCounter-1;
        
        cmdInCRCReg <= cmdInCRCReg<<1;
        datIn3CRCReg <= datIn3CRCReg<<1;
        datIn2CRCReg <= datIn2CRCReg<<1;
        datIn1CRCReg <= datIn1CRCReg<<1;
        datIn0CRCReg <= datIn0CRCReg<<1;
        
        // Reset by default to create a pulse
        cmd_accepted <= 0;
        dataOut_valid <= 0;
        dataIn_accepted <= 0;
        
        blockCounter <= blockCounter-1;
        
        
        
        
        
        
        
        case (respState)
        RespStateIdle: begin
        end
        
        RespStateIn: begin
            cmdInCRCRst_ <= 0; // Keep CRC in reset until the response starts
            if (!cmdInStaged) begin
                cmdInCRCRst_ <= 1;
                respState <= RespStateIn+1;
            end
        end
        
        RespStateIn+1: begin
            if (!cmdInReg[39]) begin
                // $display("MEOW cmdInCRC: %b", cmdInCRC);
                cmdInCRCReg <= cmdInCRC;
                respState <= RespStateIn+2;
            end
        end
        
        RespStateIn+2: begin
            // $display("HALLA cmdInCRCReg / cmdInReg: %b / %b", cmdInCRCReg, cmdInReg);
            if (!cmdInReg[47]) begin
                // $display("MEOW resp: %b", cmdInReg);
                resp <= cmdInReg;
                respState <= RespStateIn+3;
            
            end else if (cmdInCRCReg[6] !== cmdInReg[0]) begin
                $display("[SD HOST] Response: CRC bit invalid ❌");
                err <= 1;
            
            end else begin
                $display("[SD HOST] Response: CRC bit valid ✅");
            end
        end
        
        RespStateIn+3: begin
            // Check transmission and stop bits
            if (resp[46] || !resp[0]) begin
                $display("[SD HOST] Response: bad transmission/stop bit ❌");
                err <= 1;
            end else begin
                $display("[SD HOST] Response: done ✅");
            end
            
            respState <= RespStateDone;
        end
        
        RespStateDone: begin
        end
        endcase
        
        
        
        
        
        
        
        
        case (datState)
        DatStateIdle: begin
        end
        
        DatStateIn: begin
            if (!datInReg[0]) begin
                datState <= DatStateIn+1;
            end
        end
        
        DatStateIn+1: begin
            datInCRCRst_ <= 1;
            datInCounter <= 2;
            blockCounter <= 1023;
            datState <= DatStateIn+2;
        end
        
        DatStateIn+2: begin
            if (!datInCounter) begin
                datInCounter <= 3;
                dataOut <= datInReg;
                dataOut_valid <= 1;
            end
            
            if (!blockCounter) begin
                datState <= DatStateIn+3;
            end
        end
        
        // Remember the CRC we calculated
        DatStateIn+3: begin
            datInCRCRst_ <= 0;
            datIn3CRCReg <= datInCRC[3];
            datIn2CRCReg <= datInCRC[2];
            datIn1CRCReg <= datInCRC[1];
            datIn0CRCReg <= datInCRC[0];
            datInCounter <= 15;
            datState <= DatStateIn+4;
            $display("[SD HOST] DAT: calculated CRCs: %b %b %b %b", datInCRC[3], datInCRC[2], datInCRC[1], datInCRC[0]);
        end
        
        // Check CRC for each DAT line
        DatStateIn+4: begin
            // $display("EXPECTED CRCs: %h, %h, %h, %h", datIn3CRCReg, datIn2CRCReg, datIn1CRCReg, datIn0CRCReg);
            // $display("Our CRC: %h", datIn3CRCReg);
            // Handle invalid CRC
            if (datIn3CRCReg[15]!==datInReg[11] ||
                datIn2CRCReg[15]!==datInReg[10] ||
                datIn1CRCReg[15]!==datInReg[9]  ||
                datIn0CRCReg[15]!==datInReg[8]  ) begin
                $display("[SD HOST] DAT: CRC bit invalid ❌");
                err <= 1;
            
            end else begin
                $display("[SD HOST] DAT: CRC bit valid ✅");
                if (!datInCounter) begin
                    datState <= DatStateDone;
                end
            end
        end
        
        DatStateDone: begin
        end
        endcase
        
        
        
        
        
        
        
        
        
        
        
        case (state)
        StateIdle: begin
            if (cmd_trigger) begin
                cmdAddr <= cmd_addr;
                cmdWriteLen <= cmd_writeLen;
                // cmdLen <= cmd_len;
                cmd_accepted <= 1;
                state <= (cmd_write ? StateWrite : StateRead);
            end
        end
        
        StateWrite: begin
            $display("[SD HOST] Sending CMD55 (APP_CMD): %b", {2'b01, CMD55, {32{1'b0}}, 7'b0, 1'b1});
            cmdOutCmd <= CMD55;
            cmdOutRespWait <= 1;
            state <= StateCmdOut;
            nextState <= StateWrite+1;
        end
        
        StateWrite+1: begin
            $display("[SD HOST] Sending ACMD23 (SET_WR_BLK_ERASE_COUNT): %b", {2'b01, ACMD23, 9'b0, cmdWriteLen, 7'b0, 1'b1});
            cmdOutCmd <= ACMD23;
            cmdOutArg <= {9'b0, cmdWriteLen};
            cmdOutRespWait <= 1;
            state <= StateCmdOut;
            nextState <= StateWrite+2;
        end
        
        StateWrite+2: begin
            $display("[SD HOST] Sending CMD25 (WRITE_MULTIPLE_BLOCK): %b", {2'b01, CMD25, cmdAddr, 7'b0, 1'b1});
            cmdOutCmd <= CMD25;
            cmdOutArg <= cmdAddr;
            cmdOutRespWait <= 1;
            state <= StateCmdOut;
            nextState <= StateWrite+3;
        end
        
        StateWrite+3: begin
            // TODO: ensure that N_WR is met (write data starts a minimum of 2 cycles after response end)
            datOutReg <= {4'b0, dataIn};
            datOutActive <= 1;
            dataIn_accepted <= 1;
            datOutCounter <= 3;
            blockCounter <= 1023;
            state <= StateWrite+4;
        end
        
        StateWrite+4: begin
            if (!datOutCounter) begin
                datOutReg <= {dataIn, 4'b0};
                dataIn_accepted <= 1;
            end
            
            if (!blockCounter) begin
                if (cmd_trigger) begin
                    state <= StateWrite+3;
                end else begin
                    state <= StateStop;
                end
                cmd_accepted <= 1;
            end
        end
        
        
        
        
        
        
        StateRead: begin
            $display("[SD HOST] Sending CMD18 (READ_MULTIPLE_BLOCK): %b", {2'b01, CMD18, cmdAddr, 7'b0, 1'b1});
            cmdOutCmd <= CMD18;
            cmdOutArg <= cmdAddr;
            cmdOutRespWait <= 0; // Don't wait for response before transitioning to `StateRead+1`
            state <= StateCmdOut;
            nextState <= StateRead+1;
        end
        
        // TODO: check that respState==RespStateDone
        // TODO: have a watchdog countdown to ensure that we get a response
        StateRead+1: begin
            datState <= DatStateIn;
            // cmdLen <= cmdLenNext;
            state <= StateRead+2;
        end
        
        StateRead+2: begin
            if (respState===RespStateDone && datState===DatStateDone) begin
                $display("[SD HOST] Finished reading block");
                
                if (cmd_trigger) begin
                    state <= StateRead+1;
                end else begin
                    state <= StateStop;
                end
                cmd_accepted <= 1;
            end
        end
        
        
        
        StateCmdOut: begin
            cmdOutReg <= {2'b01, cmdOutCmd, cmdOutArg, 7'b0, 1'b1};
            cmdOutCounter <= 47;
            cmdOutActive <= 1;
            state <= StateCmdOut+1;
        end
        
        StateCmdOut+1: begin
            if (cmdOutCounter == 8) begin
                cmdOutReg[47:41] <= cmdOutCRC;
            
            end else if (!cmdOutCounter) begin
                cmdOutActive <= 0;
                respState <= RespStateIn;
                if (cmdOutRespWait) begin
                    state <= StateCmdOut+1;
                end else begin
                    state <= nextState;
                end
            end
        end
        
        StateCmdOut+2: begin
            if (respState === RespStateDone) begin
                state <= nextState;
            end
        end
        
        
        
        
        
        StateStop: begin
            $display("[SD HOST] Sending CMD12 (STOP_TRANSMISSION): %b", {2'b01, CMD12, {32{1'b0}}, 7'b0, 1'b1});
            cmdOutCmd <= CMD12;
            cmdOutRespWait <= 1;
            state <= StateCmdOut;
            nextState <= StateIdle;
        end
        endcase
    end
endmodule
