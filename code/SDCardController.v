`include "Util.v"
`include "CRC7.v"
`include "CRC16.v"
`include "ShiftAdder.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

// TODO: we may want to add support for partial reads, so we don't have to read a full block if the client only wants a few bytes

// TODO: for perf, try removing StateCmdOut state (the way we used to have it) so that the calling state sets up the registers.

// TODO: try merging datIn/datOut CRC modules

// TODO: for CRC16_dat, try using dout instead of doutNext. we'll need to add another cycle of latency to do that though

// TODO: try merging datInReg/datOutReg

// TODO: try merging CRC7_cmdIn/CRC7_cmdOut

// TODO: try merging datOutCounter/datInCounter





// TODO: try merging datBlockCounter/datBlockCounter
//   √

// TODO: try merging datOutActive/datOutCRCRst_
//   √

// TODO: try merging CRC16_datOut/CRC16_datIn
//   √

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
    wire[3:0] sd_datOut = datOutReg[23:20];
    wire sd_datOutActive = datOutActive[1];
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
    localparam StateWrite       = 1;    // +5
    localparam StateRead        = 7;    // +3
    localparam StateStop        = 11;   // +1
    localparam StateCmdOut      = 13;   // +4
    localparam StateLast        = 17;   // +3
    reg[4:0] state = 0;
    reg[4:0] nextState = 0;
    initial `assert(`fits(state, StateLast));
    
    localparam RespState_Idle   = 0;    // +0
    localparam RespState_Go     = 1;    // +3
    localparam RespState_Done   = 5;    // +0
    reg[3:0] respState = 0;
    
    localparam DatOutState_Idle = 0;    // +0
    localparam DatOutState_Go   = 1;    // +7
    localparam DatOutState_Done = 9;    // +0
    reg[3:0] datOutState = 0;
    
    localparam DatInState_Idle  = 0;    // +0
    localparam DatInState_Go    = 1;    // +4
    localparam DatInState_Done  = 6;    // +0
    reg[3:0] datInState = 0;
    
    localparam CMD0 =   6'd0;       // GO_IDLE_STATE
    localparam CMD12 =  6'd12;      // STOP_TRANSMISSION
    localparam CMD18 =  6'd18;      // READ_MULTIPLE_BLOCK
    localparam CMD25 =  6'd25;      // WRITE_MULTIPLE_BLOCK
    localparam CMD55 =  6'd55;      // APP_CMD
    
    localparam ACMD23 = 6'd23;      // SET_WR_BLK_ERASE_COUNT
    
    reg cmdInStaged = 0;
    reg[47:0] cmdInReg = 0;
    wire cmdIn = sd_cmdIn;
    
    reg[47:0] resp = 0;
    
    wire[3:0] datIn = sd_datIn;
    reg[19:0] datInReg = 0; // TODO: try switching back to 15:0. we added 4 more bits for checking CRC status token (which is 5 bits total)
    wire[4:0] datInCRCStatus = {datInReg[16], datInReg[12], datInReg[8], datInReg[4], datInReg[0]};
    reg[3:0] datInCounter = 0;
    
    reg[23:0] datOutReg = 0;
    reg[3:0] datOutCounter = 0;
    reg[1:0] datOutActive = 0;
    
    reg[9:0] datBlockCounter = 0;
    
    reg cmdOutActive = 0;
    reg[47:0] cmdOutReg = 0;
    reg[5:0] cmdOutCmd = 0;
    reg[31:0] cmdOutArg = 0;
    wire cmdOut = cmdOutReg[47];
    reg[5:0] cmdOutCounter = 0;
    
    reg cmdWrite = 0;
    reg[31:0] cmdAddr = 0;
    reg[22:0] cmdWriteLen = 0;
    
    
    // ====================
    // CRC (CMD in)
    // ====================
    wire[6:0] cmdCRC;
    wire cmdCRCRst_ = (state===StateCmdOut+1 || respState===RespState_Go+1);
    CRC7 CRC7_cmd(
        .clk(clk),
        .rst_(cmdCRCRst_),
        .din((cmdOutActive ? cmdOutReg[47] : cmdInReg[0])),
        .dout(),
        .doutNext(cmdCRC)
    );
    
    reg[6:0] cmdCRCReg = 0;
    
    
    
    // ====================
    // CRC (DAT)
    // ====================
    wire[15:0] datCRC[3:0];
    reg datCRCRst_ = 0;
    reg datCRCDatOut = 0;
    for (i=0; i<4; i=i+1) begin
        CRC16 CRC16_dat(
            .clk(clk),
            .rst_(datCRCRst_),
            .din(datCRCDatOut ? datOutReg[12+i] : datInReg[4+i]),
            .dout(datCRC[i]),
            .doutNext()
        );
    end
    
    reg[15:0] dat3CRCReg = 0;
    reg[15:0] dat2CRCReg = 0;
    reg[15:0] dat1CRCReg = 0;
    reg[15:0] dat0CRCReg = 0;
    
    
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
        datOutActive <= {datOutActive[0], datOutActive[0]};
        
        cmdCRCReg <= cmdCRCReg<<1;
        
        dat3CRCReg <= dat3CRCReg<<1;
        dat2CRCReg <= dat2CRCReg<<1;
        dat1CRCReg <= dat1CRCReg<<1;
        dat0CRCReg <= dat0CRCReg<<1;
        
        // Reset by default to create a pulse
        cmd_accepted <= 0;
        dataOut_valid <= 0;
        dataIn_accepted <= 0;
        
        datBlockCounter <= datBlockCounter-1;
        
        
        
        
        
        
        
        case (respState)
        RespState_Idle: begin
        end
        
        RespState_Go: begin
            if (!cmdInStaged) begin
                respState <= RespState_Go+1;
            end
        end
        
        RespState_Go+1: begin
            if (!cmdInReg[39]) begin
                $display("[SD CTRL] Response: Our CRC: %b", cmdCRC);
                cmdCRCReg <= cmdCRC;
                respState <= RespState_Go+2;
            end
        end
        
        RespState_Go+2: begin
            if (!cmdInReg[47]) begin
                $display("[SD CTRL] Response: Their CRC: %b (%b)", cmdInReg[7:1], cmdInReg);
                resp <= cmdInReg;
                respState <= RespState_Go+3;
            
            end else if (cmdCRCReg[6] !== cmdInReg[0]) begin
                $display("[SD CTRL] Response: CRC bit invalid ❌");
                err <= 1;
            
            end else begin
                $display("[SD CTRL] Response: CRC bit valid ✅");
            end
        end
        
        RespState_Go+3: begin
            // Check transmission and stop bits
            if (resp[46] || !resp[0]) begin
                $display("[SD CTRL] Response: bad transmission/stop bit ❌");
                err <= 1;
            end else begin
                $display("[SD CTRL] Response: done ✅");
            end
            
            respState <= RespState_Done;
        end
        
        RespState_Done: begin
        end
        endcase
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        case (datOutState)
        DatOutState_Idle: begin
        end
        
        DatOutState_Go: begin
            $display("[SD CTRL] DatOut: started");
            // TODO: ensure that N_WR is met (write data starts a minimum of 2 cycles after response end)
            // $display("[SD CTRL] DatOut: wrote 16 bits");
            datOutReg <= 0;
            datOutCounter <= 0;
            datBlockCounter <= 1023;
            datCRCDatOut <= 1;
            datOutActive[0] <= 1;
            datOutState <= DatOutState_Go+1;
        end
        
        DatOutState_Go+1: begin
            if (!datBlockCounter) begin
                datOutState <= DatOutState_Go+2;
            
            end else if (!datOutCounter) begin
                datCRCRst_ <= 1;
                datOutCounter <= 3;
                datOutReg[15:0] <= dataIn;
                dataIn_accepted <= 1;
            end
        end
        
        // Output CRCs
        DatOutState_Go+2: begin
            $display("[SD CTRL] CCC DatOut: CRCs: %h %h %h %h", datCRC[3], datCRC[2], datCRC[1], datCRC[0]);
            dat3CRCReg <= datCRC[3];
            dat2CRCReg <= datCRC[2];
            dat1CRCReg <= datCRC[1];
            dat0CRCReg <= datCRC[0];
            datOutState <= DatOutState_Go+3;
            datOutCounter <= 15;
        end
        
        // TODO: try loading datOutReg entirely so we only do this 4 times instead of 16
        DatOutState_Go+3: begin
            datOutReg <= {
                dat3CRCReg[15],
                dat2CRCReg[15],
                dat1CRCReg[15],
                dat0CRCReg[15],
                20'b0
            };
            
            if (!datOutCounter) begin
                datOutState <= DatOutState_Go+4;
            end
        end
        
        // End bit
        DatOutState_Go+4: begin
            datOutReg[23:20] <= 4'b1111;
            datOutState <= DatOutState_Go+5;
        end
        
        DatOutState_Go+5: begin
            datOutActive <= 0;
            datCRCRst_ <= 0;
            datOutCounter <= 7;
            datOutState <= DatOutState_Go+6;
        end
        
        // Check CRC status token
        DatOutState_Go+6: begin
            if (!datOutCounter) begin
                // 5 bits: start bit, CRC status, end bit
                if (datInCRCStatus !== 5'b0_010_1) begin
                    $display("[SD CTRL] DatOut: CRC status invalid ❌");
                    err <= 1;
                end else begin
                    $display("[SD CTRL] DatOut: CRC status valid ✅");
                end
                datOutState <= DatOutState_Go+7;
            end
        end
        
        // Wait until the card stops being busy (busy == DAT0 low)
        DatOutState_Go+7: begin
            if (datInReg[0]) begin
                $display("[SD CTRL] DatOut: Card ready");
                datOutState <= DatOutState_Done;
            end else begin
                $display("[SD CTRL] DatOut: Card busy");
            end
        end
        
        DatOutState_Done: begin
        end
        endcase
        
        
        
        
        
        
        
        
        
        
        
        
        
        case (datInState)
        DatInState_Idle: begin
        end
        
        DatInState_Go: begin
            if (!datInReg[0]) begin
                $display("[SD CTRL] DAT IN: started");
                datInState <= DatInState_Go+1;
            end
        end
        
        DatInState_Go+1: begin
            datCRCRst_ <= 1;
            datCRCDatOut <= 0;
            datInCounter <= 2;
            datBlockCounter <= 1023;
            datInState <= DatInState_Go+2;
        end
        
        DatInState_Go+2: begin
            if (!datInCounter) begin
                datInCounter <= 3;
                dataOut <= datInReg;
                dataOut_valid <= 1;
            end
            
            if (!datBlockCounter) begin
                datInState <= DatInState_Go+3;
            end
        end
        
        // Remember the CRC we calculated
        DatInState_Go+3: begin
            datCRCRst_ <= 0;
            dat3CRCReg <= datCRC[3];
            dat2CRCReg <= datCRC[2];
            dat1CRCReg <= datCRC[1];
            dat0CRCReg <= datCRC[0];
            datInCounter <= 15;
            datInState <= DatInState_Go+4;
            $display("[SD CTRL] DAT: calculated CRCs: %h %h %h %h", datCRC[3], datCRC[2], datCRC[1], datCRC[0]);
        end
        
        // Check CRC for each DAT line
        DatInState_Go+4: begin
            // $display("EXPECTED CRCs: %h, %h, %h, %h", dat3CRCReg, dat2CRCReg, dat1CRCReg, dat0CRCReg);
            // $display("Our CRC: %h", dat3CRCReg);
            // Handle invalid CRC
            if (dat3CRCReg[15]!==datInReg[11] ||
                dat2CRCReg[15]!==datInReg[10] ||
                dat1CRCReg[15]!==datInReg[9]  ||
                dat0CRCReg[15]!==datInReg[8]  ) begin
                $display("[SD CTRL] DAT: CRC bit invalid ❌");
                err <= 1;
            
            end else begin
                $display("[SD CTRL] DAT: CRC bit valid ✅");
                if (!datInCounter) begin
                    $display("[SD CTRL] DAT IN: finished");
                    datInState <= DatInState_Done;
                end
            end
        end
        
        DatInState_Done: begin
        end
        endcase
        
        
        
        
        
        
        
        
        
        
        
        case (state)
        StateIdle: begin
            if (cmd_trigger) begin
                cmdAddr <= cmd_addr;
                cmdWriteLen <= cmd_writeLen;
                cmd_accepted <= 1;
                state <= (cmd_write ? StateWrite : StateRead);
            end
        end
        
        StateWrite: begin
            $display("[SD CTRL] Sending CMD55 (APP_CMD): %b", {2'b01, CMD55, {32{1'b0}}, 7'b0, 1'b1});
            cmdOutCmd <= CMD55;
            state <= StateCmdOut;
            nextState <= StateWrite+1;
        end
        
        StateWrite+1: begin
            $display("[SD CTRL] Sending ACMD23 (SET_WR_BLK_ERASE_COUNT): %b", {2'b01, ACMD23, 9'b0, cmdWriteLen, 7'b0, 1'b1});
            cmdOutCmd <= ACMD23;
            cmdOutArg <= {9'b0, cmdWriteLen};
            state <= StateCmdOut;
            nextState <= StateWrite+2;
        end
        
        StateWrite+2: begin
            $display("[SD CTRL] Sending CMD25 (WRITE_MULTIPLE_BLOCK): %b", {2'b01, CMD25, cmdAddr, 7'b0, 1'b1});
            cmdOutCmd <= CMD25;
            cmdOutArg <= cmdAddr;
            state <= StateCmdOut;
            nextState <= StateWrite+3;
        end
        
        StateWrite+3: begin
            datOutState <= DatOutState_Go;
            state <= StateWrite+4;
        end
        
        StateWrite+4: begin
            if (datOutState === DatOutState_Done) begin
                $display("[SD CTRL] Finished writing block");
                state <= (cmd_trigger ? StateWrite+3 : StateStop);
                cmd_accepted <= 1;
            end
        end
        
        
        
        
        
        
        StateRead: begin
            $display("[SD CTRL] Sending CMD18 (READ_MULTIPLE_BLOCK): %b", {2'b01, CMD18, cmdAddr, 7'b0, 1'b1});
            cmdOutCmd <= CMD18;
            cmdOutArg <= cmdAddr;
            state <= StateCmdOut;
            nextState <= StateRead+1;
        end
        
        // TODO: check that respState==RespState_Done
        // TODO: have a watchdog countdown to ensure that we get a response
        StateRead+1: begin
            datInState <= DatInState_Go;
            state <= StateRead+2;
        end
        
        StateRead+2: begin
            if (respState===RespState_Done && datInState===DatInState_Done) begin
                $display("[SD CTRL] Finished reading block");
                state <= (cmd_trigger ? StateRead+1 : StateStop);
                cmd_accepted <= 1;
            end
        end
        
        
        
        
        
        StateStop: begin
            $display("[SD CTRL] Sending CMD12 (STOP_TRANSMISSION): %b", {2'b01, CMD12, {32{1'b0}}, 7'b0, 1'b1});
            cmdOutCmd <= CMD12;
            state <= StateCmdOut;
            nextState <= StateStop+1;
        end
        
        // Wait for the card to not be busy (DAT0=1).
        // This is only needed for writing, since the card starts
        // programming upon receipt of the stop command.
        // The card doesn't signal busy in the case of reading.
        StateStop+1: begin
            if (datInReg[0]) begin
                $display("[SD CTRL] StateStop: Card ready");
                state <= StateIdle;
            end else begin
                $display("[SD CTRL] StateStop: Card busy");
            end
        end
        
        
        
        
        StateCmdOut: begin
            cmdOutReg <= {2'b01, cmdOutCmd, cmdOutArg, 7'b0, 1'b1};
            cmdOutCounter <= 47;
            cmdOutActive <= 1;
            state <= StateCmdOut+1;
        end
        
        StateCmdOut+1: begin
            case (cmdOutCounter)
            8: cmdOutReg[47:41] <= cmdCRC;
            0: state <= StateCmdOut+2;
            endcase
        end
        
        StateCmdOut+2: begin
            cmdOutActive <= 0;
            respState <= RespState_Go;
            state <= (nextState===StateRead+1 ? StateRead+1 : StateCmdOut+3);
        end
        
        StateCmdOut+3: begin
            if (respState === RespState_Done) begin
                state <= nextState;
            end
        end
        endcase
    end
endmodule
