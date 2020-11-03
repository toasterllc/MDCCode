`include "../Util/Util.v"
`include "../Util/Sync.v"
`include "../Util/TogglePulse.v"
`include "../Util/ToggleAck.v"
`include "../Util/ClockGen.v"
`include "../Util/MsgChannel.v"
`include "../Util/CRC7.v"
`include "../Util/CRC16.v"
`include "../Util/BankFifo.v"
`include "../Util/Delay.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`ifdef SIM
`include "../Util/SDCardSim.v"
`endif

`timescale 1ns/1ps

`define Msg_Len                         64
`define Msg_Len_Cmd                     8
`define Msg_Len_Arg                     56

`define Msg_Range_Cmd                   63:56
`define Msg_Range_Arg                   55:0

`define Msg_Cmd_Echo                    `Msg_Len_Cmd'h00
`define Msg_Cmd_SDSetClkSrc             `Msg_Len_Cmd'h01
`define Msg_Cmd_SDSendCmd               `Msg_Len_Cmd'h02
`define Msg_Cmd_SDGetStatus             `Msg_Len_Cmd'h03
`define Msg_Cmd_SDDatOut                `Msg_Len_Cmd'h04
`define Msg_Cmd_None                    `Msg_Len_Cmd'hFF

`define MsgArg_Range_SDDatInExpected    49:49
`define MsgArg_Range_SDRespExpected     48:48
`define MsgArg_Range_SDCmd              47:0

`define Resp_Len                        `Msg_Len
`define Resp_Range_Arg                  63:0

`define Resp_Range_SDDat                63:60
`define Resp_Range_SDCmdSent            59:59
`define Resp_Range_SDRespRecv           58:58
`define Resp_Range_SDDatOutIdle         57:57
`define Resp_Range_SDDatInRecv          56:56

`define Resp_Range_SDRespCRCErr         55:55
`define Resp_Range_SDDatOutCRCErr       54:54
`define Resp_Range_SDDatInCRCErr        53:53

`define Resp_Range_SDFiller             52:48
`define Resp_Range_SDResp               47:0

module Top(
    input wire          clk24mhz,
    
    input wire          ctrl_clk,
    input wire          ctrl_rst,
    input wire          ctrl_di,
    output wire         ctrl_do,
    
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
    
    // output wire[3:0]    led
);
    // ====================
    // Shared Nets/Registers
    // ====================
    wire ctrl_rst_;
    wire ctrl_din;
    reg ctrl_sdClkFast = 0;
    reg ctrl_sdClkSlow = 0;
    reg ctrl_sdCmdOutTrigger = 0;
    reg ctrl_sdDatOutTrigger = 0;
    reg[`Msg_Len-1:0] ctrl_dinReg = 0;
    wire[`Msg_Len_Cmd-1:0] ctrl_msgCmd = ctrl_dinReg[`Msg_Range_Cmd];
    wire[`Msg_Len_Arg-1:0] ctrl_msgArg = ctrl_dinReg[`Msg_Range_Arg];
    reg ctrl_sdRespExpected = 0;
    reg ctrl_sdDatInExpected = 0;
    reg[47:0] ctrl_sdCmd = 0;
    
    // assign led[0] = ctrl_sdClkSlow;
    // assign led[1] = ctrl_sdClkFast;
    
    
    
    // // ====================
    // // Fast Clock (207 MHz)
    // // ====================
    // localparam FastClkFreq = 207_000_000;
    // wire fastClk;
    // ClockGen #(
    //     .FREQ(FastClkFreq),
    //     .DIVR(1),
    //     .DIVF(68),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(fastClk));
    
    // // ====================
    // // Fast Clock (144 MHz)
    // // ====================
    // localparam FastClkFreq = 144_000_000;
    // wire fastClk;
    // ClockGen #(
    //     .FREQ(FastClkFreq),
    //     .DIVR(0),
    //     .DIVF(23),
    //     .DIVQ(2),
    //     .FILTER_RANGE(2)
    // ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(fastClk));
    
    // // ====================
    // // Fast Clock (162 MHz)
    // // ====================
    // localparam FastClkFreq = 162_000_000;
    // wire fastClk;
    // ClockGen #(
    //     .FREQ(FastClkFreq),
    //     .DIVR(0),
    //     .DIVF(26),
    //     .DIVQ(2),
    //     .FILTER_RANGE(2)
    // ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(fastClk));
    
    // ====================
    // Fast Clock (120 MHz)
    // ====================
    localparam FastClkFreq = 120_000_000;
    wire fastClk;
    ClockGen #(
        .FREQ(FastClkFreq),
        .DIVR(0),
        .DIVF(39),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(fastClk));
    
    // // ====================
    // // Fast Clock (48 MHz)
    // // ====================
    // localparam FastClkFreq = 48_000_000;
    // wire fastClk;
    // ClockGen #(
    //     .FREQ(FastClkFreq),
    //     .DIVR(0),
    //     .DIVF(31),
    //     .DIVQ(4),
    //     .FILTER_RANGE(2)
    // ) ClockGen_fastClk(.clkRef(clk24mhz), .clk(fastClk));
    
    // ====================
    // Slow Clock (400 kHz)
    // ====================
    localparam SlowClkFreq = 400000;
    localparam SlowClkDividerWidth = $clog2(DivCeil(FastClkFreq, SlowClkFreq));
    reg[SlowClkDividerWidth-1:0] slowClkDivider = 0;
    wire slowClk = slowClkDivider[SlowClkDividerWidth-1];
    always @(posedge fastClk) begin
        slowClkDivider <= slowClkDivider+1;
    end
    
    // ====================
    // sd_clk_int
    // ====================
    `Sync(sdClkSlow, ctrl_sdClkSlow, negedge, slowClk);
    `Sync(sdClkFast, ctrl_sdClkFast, negedge, fastClk);
    wire sd_clk_int = (sdClkSlow ? slowClk : (sdClkFast ? fastClk : 0));
    // wire sd_clk_int = fastClk;
    
    // ====================
    // sd_clk
    //   Delay `sd_clk` relative to `sd_clk_int` to correct the phase from the SD card's perspective
    // ====================
    Delay #(
        // .Count(0)
        .Count(11)
    ) Delay_sd_clk_int(
        .in(sd_clk_int),
        .out(sd_clk)
    );
    
    // ====================
    // w_clk
    // ====================
    wire w_clk = slowClkDivider[0];
    
    // ====================
    // SD Dat Out FIFO
    // ====================
    reg w_sdDatOutFifo_wtrigger = 0;
    reg[15:0] w_sdDatOutFifo_wdata = 0;
    wire w_sdDatOutFifo_wok;
    reg sd_datOutFifo_rtrigger = 0;
    wire[15:0] sd_datOutFifo_rdata;
    wire sd_datOutFifo_rok;
    wire sd_datOutFifo_rbank;
    BankFifo #(
        .W(16),
        .N(8)
    ) BankFifo_sdDatOut(
        .w_clk(w_clk),
        .w_trigger(w_sdDatOutFifo_wtrigger),
        .w_data(w_sdDatOutFifo_wdata),
        .w_ok(w_sdDatOutFifo_wok),
        
        .r_clk(sd_clk_int),
        .r_trigger(sd_datOutFifo_rtrigger),
        .r_data(sd_datOutFifo_rdata),
        .r_ok(sd_datOutFifo_rok),
        .r_bank(sd_datOutFifo_rbank)
    );
    
    // ====================
    // Writer State Machine
    // ====================
    reg[1:0] w_state = 0;
    reg[22:0] w_counter = 0;
    `TogglePulse(w_sdDatOutTrigger, ctrl_sdDatOutTrigger, posedge, w_clk);
    always @(posedge w_clk) begin
        case (w_state)
        0: begin
            w_sdDatOutFifo_wdata <= 0;
            // w_sdDatOutFifo_wdata <= 8'hFF;
            w_sdDatOutFifo_wtrigger <= 0;
            w_counter <= 0;
            if (w_sdDatOutTrigger) begin
                w_sdDatOutFifo_wtrigger <= 1;
                w_state <= 1;
            end
        end
        
        1: begin
            if (w_sdDatOutFifo_wok) begin
                w_counter <= w_counter+1;
                w_sdDatOutFifo_wdata <= w_sdDatOutFifo_wdata+1;
            end
`ifdef SIM
            if (w_counter === 'h800-2) begin
`else
            if (w_counter === (2304*1296)-2) begin
`endif
            // if (w_counter === 'hFE) begin
                w_state <= 0;
            end
        end
        endcase
    end
    
    // ====================
    // SD State Machine
    // ====================
    reg[11:0] sd_cmdOutState = 0;
    reg sd_cmdOutStateInit = 0;
    
    reg[9:0] sd_respState = 0;
    reg sd_respStateInit = 0;
    
    reg[47:0] sd_cmdRespShiftReg = 0;
    
    reg sd_cmdOutCRCEn = 0;
    reg sd_cmdOutCRCOutEn = 0;
    reg sd_cmdSent = 0;
    reg[2:0] sd_cmdOutActive = 0; // 3 bits -- see explanation where assigned
    reg[5:0] sd_cmdOutCounter = 0;
    wire sd_cmdIn;
    wire sd_cmdOutCRC;
    
    reg sd_respCRCEn = 0;
    reg sd_respCRCErr = 0;
    reg sd_respGo = 0;
    reg sd_respRecv = 0;
    reg sd_respStaged = 0;
    reg[47:0] sd_resp = 0;
    wire sd_respCRC;
    
    reg[2:0] sd_datOutState = 0;
    reg[2:0] sd_datOutActive = 0; // 3 bits -- see explanation where assigned
    reg sd_datOutCRCEn = 0;
    reg sd_datOutCRCErr = 0;
    reg sd_datOutCRCOutEn = 0;
    reg sd_datOutEndBit = 0;
    reg sd_datOutEnding = 0;
    reg sd_datOutLastBank = 0;
    reg sd_datOutStartBit = 0;
    reg[19:0] sd_datOutReg = 0;
    reg[1:0] sd_datOutCounter = 0;
    reg[3:0] sd_datOutCRCCounter = 0;
    wire[3:0] sd_datOutCRC;
    // TODO: rename these if they're only used by the datOut state machines
    wire[4:0] sd_datInCRCStatus = {sd_datInReg[16], sd_datInReg[12], sd_datInReg[8], sd_datInReg[4], sd_datInReg[0]};
    wire sd_datInCRCStatusOK = sd_datInCRCStatus===5'b0_010_1; // 5 bits: start bit, CRC status, end bit
    reg sd_datInCRCStatusOKReg = 0;
    reg[1:0] sd_datOutIdleReg = 0; // 2 bits -- see explanation where it's assigned
    
    reg[4:0] sd_datInState = 0;
    reg sd_datInStateInit = 0;
    reg sd_datInGo = 0;
    wire[3:0] sd_datIn;
    reg[19:0] sd_datInReg = 0;
    reg sd_datInCRCEn = 0;
    wire[3:0] sd_datInCRC;
    reg sd_datInRecv = 0;
    reg sd_datInCRCErr = 0;
    reg[6:0] sd_datInCounter = 0;
    reg[3:0] sd_datInCRCCounter = 0;
    
    `TogglePulse(sd_cmdOutTrigger, ctrl_sdCmdOutTrigger, posedge, sd_clk_int);
    
    always @(posedge sd_clk_int) begin
        // ====================
        // CmdOut State Machine
        // ====================
        sd_cmdOutState <= sd_cmdOutState<<1|!sd_cmdOutStateInit|sd_cmdOutState[$size(sd_cmdOutState)-1];
        sd_cmdOutStateInit <= 1;
        sd_cmdOutCounter <= sd_cmdOutCounter-1;
        // `sd_cmdOutActive` is 3 bits to track whether `sd_cmdIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        sd_cmdOutActive <= (sd_cmdOutActive<<1)|sd_cmdOutActive[0];
        
        sd_cmdRespShiftReg <= sd_cmdRespShiftReg<<1|sd_respStaged;
        if (sd_cmdOutCRCOutEn)  sd_cmdRespShiftReg[47] <= sd_cmdOutCRC;
        
        if (sd_cmdOutState[0]) begin
            sd_cmdOutActive[0] <= 0;
            sd_cmdOutCounter <= 38;
            if (sd_cmdOutTrigger) begin
                $display("[SD-CTRL:CMDOUT] Command to be clocked out: %b", ctrl_msgArg[47:0]);
            end else begin
                // Stay in this state
                sd_cmdOutState[1:0] <= sd_cmdOutState[1:0];
            end
        end
        
        if (sd_cmdOutState[1]) begin
            sd_cmdOutActive[0] <= 1;
            sd_cmdRespShiftReg <= ctrl_sdCmd;
            sd_cmdOutCRCEn <= 1;
        end
        
        if (sd_cmdOutState[2]) begin
            if (sd_cmdOutCounter) begin
                // Stay in this state
                sd_cmdOutState[3:2] <= sd_cmdOutState[3:2];
            end
        end
        
        if (sd_cmdOutState[3]) begin
            sd_cmdOutCRCOutEn <= 1;
        end
        
        if (sd_cmdOutState[4]) begin
            sd_cmdOutCRCEn <= 0;
        end
        
        if (sd_cmdOutState[10]) begin
            sd_cmdOutCRCOutEn <= 0;
            sd_cmdSent <= !sd_cmdSent;
            sd_respGo <= ctrl_sdRespExpected;
            sd_datInGo <= ctrl_sdDatInExpected;
        end
        
        
        
        
        // ====================
        // Resp State Machine
        // ====================
        sd_respState <= sd_respState<<1|!sd_respStateInit|sd_respState[$size(sd_respState)-1];
        sd_respStateInit <= 1;
        sd_respStaged <= sd_cmdOutActive[2] ? 1'b1 : sd_cmdIn;
        
        if (sd_respState[0]) begin
            sd_respCRCEn <= 0;
            sd_respCRCErr <= 0;
            if (sd_respGo && !sd_respStaged) begin
                sd_respGo <= 0;
                sd_respCRCEn <= 1;
            end else begin
                // Stay in this state
                sd_respState[1:0] <= sd_respState[1:0];
            end
        end
        
        if (sd_respState[1]) begin
            if (!sd_cmdRespShiftReg[40]) begin
                sd_respCRCEn <= 0;
            end else begin
                sd_respState[2:1] <= sd_respState[2:1];
            end
        end
        
        if (sd_respState[8:2]) begin
            if (sd_respCRC === sd_cmdRespShiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good CRC bit (ours: %b, theirs: %b) ✅", sd_respCRC, sd_cmdRespShiftReg[1]);
            end else begin
                sd_respCRCErr <= sd_respCRCErr|1;
                $display("[SD-CTRL:RESP] Response: Bad CRC bit (ours: %b, theirs: %b) ❌", sd_respCRC, sd_cmdRespShiftReg[1]);
                // `Finish;
            end
        end
        
        if (sd_respState[9]) begin
            // Ideally we'd assign `sd_resp` on the previous clock cycle
            // so that we didn't need this right-shift, but that hurts
            // our perf quite a bit. So since the high bit of SD card
            // commands/responses is always zero, assign it here.
            sd_resp <= sd_cmdRespShiftReg>>1;
            // Signal that the response was received
            sd_respRecv <= !sd_respRecv;
        end
        
        
        
        
        // ====================
        // DatOut State Machine
        // ====================
        sd_datOutCounter <= sd_datOutCounter-1;
        sd_datOutCRCCounter <= sd_datOutCRCCounter-1;
        sd_datOutFifo_rtrigger <= 0; // Pulse
        sd_datOutLastBank <= sd_datOutFifo_rbank;
        sd_datOutEnding <= sd_datOutEnding|(sd_datOutLastBank && !sd_datOutFifo_rbank);
        sd_datOutStartBit <= 0; // Pulse
        sd_datOutEndBit <= 0; // Pulse
        sd_datOutIdleReg <= sd_datOutIdleReg<<1;
        sd_datInCRCStatusOKReg <= sd_datInCRCStatusOK;
        sd_datOutReg <= sd_datOutReg<<4;
        if (!sd_datOutCounter)  sd_datOutReg[15:0] <= sd_datOutFifo_rdata;
        if (sd_datOutCRCOutEn)  sd_datOutReg[19:16] <= sd_datOutCRC;
        if (sd_datOutStartBit)  sd_datOutReg[19:16] <= 4'b0000;
        if (sd_datOutEndBit)    sd_datOutReg[19:16] <= 4'b1111;
        
        // `sd_datOutActive` is 3 bits to track whether `sd_datIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        sd_datOutActive <= (sd_datOutActive<<1)|sd_datOutActive[0];
        
        case (sd_datOutState)
        0: begin
            sd_datOutCounter <= 0;
            sd_datOutCRCCounter <= 0;
            sd_datOutActive[0] <= 0;
            sd_datOutEnding <= 0;
            sd_datOutCRCEn <= 0;
            sd_datOutStartBit <= 1;
            // Use 2 bits for sd_datOutIdleReg, so that if they're both 1,
            // we know that we're actually idle, since being in this state
            // more than one cycle implies that the FIFO's rok=0
            sd_datOutIdleReg[0] <= 1;
            if (sd_datOutFifo_rok) begin
                $display("[SD-CTRL:DATOUT] Write another block to SD card");
                sd_datOutState <= 1;
            end
        end
        
        1: begin
            sd_datOutActive[0] <= 1;
            sd_datOutCRCEn <= 1;
            
            if (!sd_datOutCounter) begin
                // $display("[SD-CTRL:DATOUT]   Write another word: %x", sd_datOutFifo_rdata);
                sd_datOutFifo_rtrigger <= 1;
            end
            
            if (sd_datOutEnding) begin
                $display("[SD-CTRL:DATOUT] Done writing");
                sd_datOutState <= 2;
            end
        end
        
        // Wait for CRC to be clocked out and supply end bit
        2: begin
            sd_datOutCRCOutEn <= 1;
            sd_datOutState <= 3;
        end
        
        3: begin
            if (!sd_datOutCRCCounter) begin
                sd_datOutCRCEn <= 0;
                sd_datOutEndBit <= 1;
                sd_datOutState <= 4;
            end
        end
        
        // Check CRC status token
        4: begin
            sd_datOutCRCOutEn <= 0;
            if (sd_datOutCRCCounter === 14) begin
                sd_datOutActive[0] <= 0;
            end
            
            if (sd_datOutCRCCounter === 4) begin
                sd_datOutState <= 5;
            end
        end
        
        // Wait until the card stops being busy (busy == DAT0 low)
        5: begin
            $display("[SD-CTRL:DATOUT] DatOut: sd_datInCRCStatusOKReg: %b", sd_datInCRCStatusOKReg);
            // 5 bits: start bit, CRC status, end bit
            if (sd_datInCRCStatusOKReg) begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status valid ✅");
            end else begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status invalid: %b ❌", sd_datInCRCStatusOKReg);
                sd_datOutCRCErr <= 1;
            end
            sd_datOutState <= 6;
        end
        
        6: begin
            if (sd_datInReg[0]) begin
                $display("[SD-CTRL:DATOUT] Card ready");
                sd_datOutState <= 0;
            end else begin
                $display("[SD-CTRL:DATOUT] Card busy");
            end
        end
        endcase
        
        
        
        
        
        // TODO: test traditional state machine style (like the DatOut state machine) vs this one-hot style, and use the faster one
        // ====================
        // DatIn State Machine
        // ====================
        sd_datInState <= sd_datInState<<1|!sd_datInStateInit|sd_datInState[$size(sd_datInState)-1];
        sd_datInStateInit <= 1;
        sd_datInReg <= (sd_datInReg<<4)|(sd_datOutActive[2] ? 4'b1111 : {sd_datIn[3], sd_datIn[2], sd_datIn[1], sd_datIn[0]});
        sd_datInCounter <= sd_datInCounter-1;
        sd_datInCRCCounter <= sd_datInCRCCounter-1;
        if (sd_datInState[0]) begin
            sd_datInCounter <= 127;
            sd_datInCRCEn <= 0;
            if (sd_datInGo && !sd_datInReg[0]) begin
                $display("[SD-CTRL:DATIN] Triggered");
                sd_datInGo <= 0;
                sd_datInCRCEn <= 1;
            
            end else begin
                // Stay in this state
                sd_datInState[1:0] <= sd_datInState[1:0];
            end
        end
        
        if (sd_datInState[1]) begin
            if (!sd_datInCounter) begin
                sd_datInCRCEn <= 0;
            
            end else begin
                // Stay in this state
                sd_datInState[2:1] <= sd_datInState[2:1];
            end
        end
        
        if (sd_datInState[2]) begin
            sd_datInCRCCounter <= 15;
        end
        
        if (sd_datInState[3]) begin
            // $finish;
            if (sd_datInCRC[3] === sd_datInReg[7]) begin
                $display("[SD-CTRL:DATIN] DAT3 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT3 CRC ❌ (ours: %b, theirs: %b)", sd_datInCRC[3], sd_datInReg[7]);
                sd_datInCRCErr <= 1;
            end
            
            if (sd_datInCRC[2] === sd_datInReg[6]) begin
                $display("[SD-CTRL:DATIN] DAT2 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT2 CRC ❌ (ours: %b, theirs: %b)", sd_datInCRC[2], sd_datInReg[6]);
                sd_datInCRCErr <= 1;
            end
            
            if (sd_datInCRC[1] === sd_datInReg[5]) begin
                $display("[SD-CTRL:DATIN] DAT1 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT1 CRC ❌ (ours: %b, theirs: %b)", sd_datInCRC[1], sd_datInReg[5]);
                sd_datInCRCErr <= 1;
            end
            
            if (sd_datInCRC[0] === sd_datInReg[4]) begin
                $display("[SD-CTRL:DATIN] DAT0 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT0 CRC ❌ (ours: %b, theirs: %b)", sd_datInCRC[0], sd_datInReg[4]);
                sd_datInCRCErr <= 1;
            end
            
            if (sd_datInCRCCounter) begin
                // Stay in this state
                sd_datInState[4:3] <= sd_datInState[4:3];
            end
        end
        
        if (sd_datInState[4]) begin
            if (sd_datInReg[7:4] === 4'b1111) begin
                $display("[SD-CTRL:DATIN] Good end bit ✅");
            end else begin
                sd_datInCRCErr <= 1;
                $display("[SD-CTRL:DATIN] Bad end bit ❌");
            end
            // Signal that the DatIn is complete
            sd_datInRecv <= !sd_datInRecv;
        end
    end
    
    
    
    
    
    
    // ====================
    // Control State Machine
    // ====================
    reg[1:0] ctrl_state = 0;
    reg[6:0] ctrl_counter = 0;
    // +5 for delay states, so that clients send an extra byte before receiving the response
    reg[`Resp_Len+5-1:0] ctrl_doutReg = 0;
    
    wire sd_datOutIdle = &sd_datOutIdleReg;
    `ToggleAck(ctrl_sdCmdSent, ctrl_sdCmdSentAck, sd_cmdSent, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdRespRecv, ctrl_sdRespRecvAck, sd_respRecv, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatInRecv, ctrl_sdDatInRecvAck, sd_datInRecv, posedge, ctrl_clk);
    `Sync(ctrl_sdDatOutIdle, sd_datOutIdle, posedge, ctrl_clk);
    `Sync(ctrl_sdRespCRCErr, sd_respCRCErr, posedge, ctrl_clk);
    `Sync(ctrl_sdDatOutCRCErr, sd_datOutCRCErr, posedge, ctrl_clk);
    `Sync(ctrl_sdDatInCRCErr, sd_datInCRCErr, posedge, ctrl_clk);
    
    always @(posedge ctrl_clk, negedge ctrl_rst_) begin
        if (!ctrl_rst_) begin
            ctrl_state <= 0;
        
        end else begin
            ctrl_dinReg <= ctrl_dinReg<<1|ctrl_din;
            ctrl_doutReg <= ctrl_doutReg<<1|1'b1;
            ctrl_counter <= ctrl_counter-1;
            
            case (ctrl_state)
            0: begin
                ctrl_counter <= `Msg_Len-1;
                ctrl_state <= 1;
            end
            
            1: begin
                if (!ctrl_counter) begin
                    ctrl_state <= 2;
                end
            end
            
            2: begin
                // $display("[CTRL] Got command: %b [cmd: %0d, arg: %0d]", ctrl_dinReg, ctrl_msgCmd, ctrl_msgArg);
                case (ctrl_msgCmd)
                // Echo
                `Msg_Cmd_Echo: begin
                    $display("[CTRL] Got Msg_Cmd_Echo: %0h", ctrl_msgArg);
                    ctrl_doutReg[`Resp_Range_Arg] <= {ctrl_msgArg, 8'h00};
                end
                
                // Set SD clock source
                `Msg_Cmd_SDSetClkSrc: begin
                    $display("[CTRL] Got Msg_Cmd_SDSetClkSrc: %0d", ctrl_msgArg[1:0]);
                    ctrl_sdClkSlow <= ctrl_msgArg[0];
                    ctrl_sdClkFast <= ctrl_msgArg[1];
                end
                
                // Clock out SD command
                `Msg_Cmd_SDSendCmd: begin
                    $display("[CTRL] Got Msg_Cmd_SDSendCmd");
                    // Clear our signals so they can be reliably observed via SDGetStatus
                    if (ctrl_sdCmdSent) ctrl_sdCmdSentAck <= !ctrl_sdCmdSentAck;
                    if (ctrl_sdRespRecv) ctrl_sdRespRecvAck <= !ctrl_sdRespRecvAck;
                    if (ctrl_sdDatInRecv) ctrl_sdDatInRecvAck <= !ctrl_sdDatInRecvAck;
                    ctrl_sdRespExpected <= ctrl_msgArg[`MsgArg_Range_SDRespExpected];
                    ctrl_sdDatInExpected <= ctrl_msgArg[`MsgArg_Range_SDDatInExpected];
                    ctrl_sdCmd <= ctrl_msgArg[`MsgArg_Range_SDCmd];
                    ctrl_sdCmdOutTrigger <= !ctrl_sdCmdOutTrigger;
                end
                
                // Get SD status / response
                `Msg_Cmd_SDGetStatus: begin
                    $display("[CTRL] Got Msg_Cmd_SDGetStatus");
                    // We don't need a synchronizer for sd_resp because
                    // it's guarded by `ctrl_sdRespRecv`, which is synchronized.
                    // Ie, sd_resp should be ignored unless ctrl_sdRespRecv=1.
                    // TODO: add a synchronizer for `sd_datIn`
                    ctrl_doutReg[`Resp_Range_SDDat]             <= sd_datIn;
                    ctrl_doutReg[`Resp_Range_SDCmdSent]         <= ctrl_sdCmdSent;
                    ctrl_doutReg[`Resp_Range_SDRespRecv]        <= ctrl_sdRespRecv;
                    ctrl_doutReg[`Resp_Range_SDDatOutIdle]      <= ctrl_sdDatOutIdle;
                    ctrl_doutReg[`Resp_Range_SDDatInRecv]       <= ctrl_sdDatInRecv;
                    ctrl_doutReg[`Resp_Range_SDRespCRCErr]      <= ctrl_sdRespCRCErr;
                    ctrl_doutReg[`Resp_Range_SDDatOutCRCErr]    <= ctrl_sdDatOutCRCErr;
                    ctrl_doutReg[`Resp_Range_SDDatInCRCErr]     <= ctrl_sdDatInCRCErr;
                    ctrl_doutReg[`Resp_Range_SDResp]            <= sd_resp;
                end
                
                `Msg_Cmd_SDDatOut: begin
                    $display("[CTRL] Got Msg_Cmd_SDDatOut");
                    ctrl_sdDatOutTrigger <= !ctrl_sdDatOutTrigger;
                end
                
                `Msg_Cmd_None: begin
                    $display("[CTRL] Got Msg_Cmd_None");
                end
                
                default: begin
                    $display("[CTRL] BAD COMMAND: %0d ❌", ctrl_msgCmd);
                    `Finish;
                end
                endcase
                
                ctrl_state <= 0;
            end
            endcase
        end
    end
    
    // ====================
    // Pin: ctrl_rst
    // ====================
    wire ctrl_rst_tmp;
    assign ctrl_rst_ = !ctrl_rst_tmp;
    SB_IO #(
        .PIN_TYPE(6'b0000_01),
        .PULLUP(1'b1)
    ) SB_IO_ctrl_rst (
        .PACKAGE_PIN(ctrl_rst),
        .D_IN_0(ctrl_rst_tmp)
    );
    
    // ====================
    // Pin: ctrl_di
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b0000_00),
        .PULLUP(1'b1)
    ) SB_IO_ctrl_clk (
        .INPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_di),
        .D_IN_0(ctrl_din)
    );
    
    // ====================
    // Pin: ctrl_do
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_01),
        .PULLUP(1'b1)
    ) SB_IO_ctrl_do (
        .OUTPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_do),
        .OUTPUT_ENABLE(1'b1),
        .D_OUT_0(ctrl_doutReg[$size(ctrl_doutReg)-1])
    );
    
    // ====================
    // Pin: sd_cmd
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_sd_cmd (
        .INPUT_CLK(sd_clk_int),
        .OUTPUT_CLK(sd_clk_int),
        .PACKAGE_PIN(sd_cmd),
        .OUTPUT_ENABLE(sd_cmdOutActive[0]),
        .D_OUT_0(sd_cmdRespShiftReg[47]),
        .D_IN_0(sd_cmdIn)
    );
    
    // ====================
    // Pin: sd_dat[3:0]
    // ====================
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_00)
        ) SB_IO (
            .INPUT_CLK(sd_clk_int),
            .OUTPUT_CLK(sd_clk_int),
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_ENABLE(sd_datOutActive[0]),
            .D_OUT_0(sd_datOutReg[16+i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    // ====================
    // CRC: sd_cmdOutCRC
    // ====================
    CRC7 #(
        .Delay(-1)
    ) CRC7_sd_cmdOutCRC(
        .clk(sd_clk_int),
        .en(sd_cmdOutCRCEn),
        .din(sd_cmdRespShiftReg[47]),
        .dout(sd_cmdOutCRC)
    );
    
    // ====================
    // CRC: sd_respCRC
    // ====================
    CRC7 #(
        .Delay(1)
    ) CRC7_sd_respCRC(
        .clk(sd_clk_int),
        .en(sd_respCRCEn),
        .din(sd_cmdRespShiftReg[0]),
        .dout(sd_respCRC)
    );
    
    // ====================
    // CRC: sd_datOutCRC
    // ====================
    for (i=0; i<4; i=i+1) begin
        CRC16 #(
            .Delay(-1)
        ) CRC16_sd_datOutCRC(
            .clk(sd_clk_int),
            .en(sd_datOutCRCEn),
            .din(sd_datOutReg[16+i]),
            .dout(sd_datOutCRC[i])
        );
    end
    
    // ====================
    // CRC: sd_datInCRC
    // ====================
    for (i=0; i<4; i=i+1) begin
        CRC16 #(
            .Delay(1)
        ) CRC16_dat(
            .clk(sd_clk_int),
            .en(sd_datInCRCEn),
            .din(sd_datInReg[i]),
            .dout(sd_datInCRC[i])
        );
    end
endmodule







`ifdef SIM
module Testbench();
    reg         clk24mhz;
    
    reg         ctrl_clk = 1;
    reg         ctrl_rst = 1;
    tri1        ctrl_di;
    tri1        ctrl_do;
    
    wire        sd_clk;
    wire        sd_cmd;
    wire[3:0]   sd_dat;
    
    Top Top(.*);
    
    SDCardSim SDCardSim(
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, Testbench);
    end
    
    initial begin
        #100000000;
        `Finish;
    end
    
    initial begin
        forever begin
            clk24mhz = 0;
            #21;
            clk24mhz = 1;
            #21;
        end
    end
    
    localparam SD_RESP_FALSE        = 1'b0;
    localparam SD_RESP_TRUE         = 1'b1;
    
    localparam SD_DAT_IN_FALSE      = 1'b0;
    localparam SD_DAT_IN_TRUE       = 1'b1;
    
    localparam CMD0     = 6'd0;     // GO_IDLE_STATE
    localparam CMD2     = 6'd2;     // ALL_SEND_BIT_CID
    localparam CMD3     = 6'd3;     // SEND_BIT_RELATIVE_ADDR
    localparam CMD6     = 6'd6;     // SWITCH_FUNC
    localparam CMD7     = 6'd7;     // SELECT_CARD/DESELECT_CARD
    localparam CMD8     = 6'd8;     // SEND_BIT_IF_COND
    localparam CMD11    = 6'd11;    // VOLTAGE_SWITCH
    localparam CMD25    = 6'd25;    // WRITE_MULTIPLE_BLOCK
    localparam CMD41    = 6'd41;    // SD_SEND_BIT_OP_COND
    localparam CMD55    = 6'd55;    // APP_CMD
    
    localparam ACMD23    = 6'd23;   // SET_WR_BLK_ERASE_COUNT
    
    localparam CTRL_CLK_DELAY = 21;
    
    reg[`Msg_Len-1:0] ctrl_diReg;
    reg[`Resp_Len-1:0] ctrl_doReg;
    reg[`Resp_Len-1:0] resp;
    
    always @(posedge ctrl_clk) begin
        ctrl_diReg <= ctrl_diReg<<1|1'b1;
        ctrl_doReg <= ctrl_doReg<<1|ctrl_do;
    end
    
    assign ctrl_di = ctrl_diReg[`Msg_Len-1];
    
    task _SendMsg(input[`Msg_Len_Cmd-1:0] cmd, input[`Msg_Len_Arg-1:0] arg); begin
        reg[15:0] i;
        
        ctrl_rst = 0;
        #1; // Let `ctrl_rst` change take effect
            ctrl_diReg = {cmd, arg};
            for (i=0; i<`Msg_Len; i++) begin
                ctrl_clk = 1;
                #(CTRL_CLK_DELAY);
                ctrl_clk = 0;
                #(CTRL_CLK_DELAY);
            end
            
            // Clock out dummy byte
            for (i=0; i<8; i++) begin
                ctrl_clk = 1;
                #(CTRL_CLK_DELAY);
                ctrl_clk = 0;
                #(CTRL_CLK_DELAY);
            end
        ctrl_rst = 1;
        #1; // Let `ctrl_rst` change take effect
    end endtask
    
    task _Wait; begin
        // // Wait for msg to be consumed before sending another, otherwise we can overwrite
        // // the shift register while it's still being used
        // #100000;
        // wait(!ctrl_clk);
    end endtask
    
    task SendMsg(input[`Msg_Len_Cmd-1:0] cmd, input[`Msg_Len_Arg-1:0] arg); begin
        reg[15:0] i;
        
        _SendMsg(cmd, arg);
        _Wait();
    end endtask
    
    task SendMsgRecvResp(input[`Msg_Len_Cmd-1:0] cmd, input[`Msg_Len_Arg-1:0] arg); begin
        reg[15:0] i;
        
        _SendMsg(cmd, arg);
        
        // Load the response
        ctrl_rst = 0;
        #1; // Let `ctrl_rst` change take effect
            for (i=0; i<`Msg_Len; i++) begin
                ctrl_clk = 1;
                #(CTRL_CLK_DELAY);
                ctrl_clk = 0;
                #(CTRL_CLK_DELAY);
            end
        ctrl_rst = 1;
        #1; // Let `ctrl_rst` change take effect
        
        resp = ctrl_doReg;
        
        _Wait();
    end endtask
    
    task SendSDCmd(input[5:0] sdCmd, input respExpected, input datInExpected, input[31:0] sdArg); begin
        reg[`Msg_Len_Arg-1] arg;
        reg done;
        arg = 0;
        arg[`MsgArg_Range_SDRespExpected] = respExpected;
        arg[`MsgArg_Range_SDDatInExpected] = datInExpected;
        arg[`MsgArg_Range_SDCmd] = {2'b01, sdCmd, sdArg, 7'b0, 1'b1};
        
        SendMsg(`Msg_Cmd_SDSendCmd, arg);
        
        // Wait for SD command to be sent
        do begin
            // Request SD status
            SendMsgRecvResp(`Msg_Cmd_SDGetStatus, 0);
            
            // If a response is expected, we're done when the response is received
            if (respExpected) done = resp[`Resp_Range_SDRespRecv];
            // If a response isn't expected, we're done when the command is sent
            else done = resp[`Resp_Range_SDCmdSent];
        end while(!done);
    end endtask
    
    initial begin
        reg[15:0] i, ii;
        reg sdDone;
        ctrl_diReg = ~0;
        
        // SendMsgRecvResp(`Msg_Len_Cmd'hFF, 56'h66554433221100);
        // $display("Got response: %h", resp);
        // $finish;
        
        // SendMsgRecvResp(`Msg_Cmd_Echo, 56'h66554433221100);
        // $display("Got response: %h", resp);
        // $finish;
        
        // SendMsg(`Msg_Cmd_SDSetClkSrc, 2'b10);
        // SendSDCmd(CMD55, SD_RESP_TRUE, SD_DAT_IN_FALSE, 32'b0);
        // $finish;
        
        
        
        
        
        
        
        
        // // Set SD clock source = slow clock
        // SendMsg(`Msg_Cmd_SDSetClkSrc, 2'b01);
        //
        // // Send SD CMD0
        // SendSDCmd(CMD0, SD_RESP_FALSE, SD_DAT_IN_FALSE, 0);
        //
        // // Send SD CMD8
        // SendSDCmd(CMD8, SD_RESP_TRUE, SD_DAT_IN_FALSE, 32'h000001AA);
        // if (resp[`Resp_Range_SDRespCRCErr] !== 1'b0) begin
        //     $display("[EXT] CRC error ❌");
        //     $finish;
        // end
        //
        // if (resp[15:8] !== 8'hAA) begin
        //     $display("[EXT] Bad response: %h ❌", resp);
        //     $finish;
        // end
        
        
        
        
        
        
        // Disable SD clock
        SendMsg(`Msg_Cmd_SDSetClkSrc, 0);

        // Set SD clock source = fast clock
        SendMsg(`Msg_Cmd_SDSetClkSrc, 2'b10);

        // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        SendSDCmd(CMD55, SD_RESP_TRUE, SD_DAT_IN_FALSE, 32'b0);
        SendSDCmd(ACMD23, SD_RESP_TRUE, SD_DAT_IN_FALSE, 32'b1);
        
        // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        SendSDCmd(CMD25, SD_RESP_TRUE, SD_DAT_IN_FALSE, 32'b0);
        
        // Clock out data on DAT lines
        SendMsg(`Msg_Cmd_SDDatOut, 0);

        // Wait some pre-determined amount of time that guarantees
        // that we've started writing to the SD card.
        #10000;

        // Wait until we're done clocking out data on DAT lines
        $display("[EXT] Waiting while data is written...");
        do begin
            // Request SD status
            SendMsgRecvResp(`Msg_Cmd_SDGetStatus, 0);
        end while(!resp[`Resp_Range_SDDatOutIdle]);
        $display("[EXT] Done writing");

        // Check CRC status
        if (resp[`Resp_Range_SDDatOutCRCErr] === 1'b0) begin
            $display("[EXT] DatOut CRC OK ✅");
        end else begin
            $display("[EXT] DatOut CRC bad ❌");
        end

        
        
        
        
        
        
        
        
        
        
        // // Disable SD clock
        // SendMsg(`Msg_Cmd_SDSetClkSrc, 0);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Cmd_SDSetClkSrc, 2'b10);
        //
        // // Send SD command CMD6 (SWITCH_FUNC)
        // SendSDCmd(CMD6, SD_RESP_TRUE, SD_DAT_IN_TRUE, 32'h80FFFFF3);
        // $display("[EXT] Waiting for DatIn to complete...");
        // do begin
        //     // Request SD status
        //     SendMsgRecvResp(`Msg_Cmd_SDGetStatus, 0);
        // end while(!resp[`Resp_Range_SDDatInRecv]);
        // $display("[EXT] DatIn completed");
        //
        // // Check DatIn CRC status
        // if (resp[`Resp_Range_SDDatInCRCErr] === 1'b0) begin
        //     $display("[EXT] DatIn CRC OK ✅");
        // end else begin
        //     $display("[EXT] DatIn CRC bad ❌");
        // end
        
    end
endmodule
`endif
