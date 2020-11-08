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
`include "../Util/VariableDelay.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`ifdef SIM
`include "../Util/SDCardSim.v"
`endif

`timescale 1ns/1ps

// TODO: rename the _Range constants to _Bits

// ====================
// Control Messages/Responses
// ====================
`define Msg_Len                                         64

`define Msg_Type_Len                                    8
`define Msg_Type_Range                                  63:56

`define Msg_Arg_Len                                     56
`define Msg_Arg_Range                                   55:0

`define Resp_Len                                        `Msg_Len
`define Resp_Arg_Range                                  63:0

`define Msg_Type_Echo                                   `Msg_Type_Len'h00
`define Msg_Type_SDClkSet                               `Msg_Type_Len'h01
`define     Msg_Arg_SDClkDelay_Range                    5:2
`define     Msg_Arg_SDClkSrc_Len                        2
`define     Msg_Arg_SDClkSrc_Range                      1:0
`define     Msg_Arg_SDClkSrc_None                       `Msg_Arg_SDClkSrc_Len'b00
`define     Msg_Arg_SDClkSrc_Slow                       `Msg_Arg_SDClkSrc_Len'b01
`define     Msg_Arg_SDClkSrc_Slow_Range                 0:0
`define     Msg_Arg_SDClkSrc_Fast                       `Msg_Arg_SDClkSrc_Len'b10
`define     Msg_Arg_SDClkSrc_Fast_Range                 1:1

`define Msg_Type_SDSendCmd                              `Msg_Type_Len'h02
`define     Msg_Arg_SDRespType_Len                      2
`define     Msg_Arg_SDRespType_Range                    49:48
`define     Msg_Arg_SDRespType_0                        `Msg_Arg_SDRespType_Len'b00
`define     Msg_Arg_SDRespType_48                       `Msg_Arg_SDRespType_Len'b01
`define     Msg_Arg_SDRespType_48_Range                 0:0
`define     Msg_Arg_SDRespType_136                      `Msg_Arg_SDRespType_Len'b10
`define     Msg_Arg_SDRespType_136_Range                1:1
`define     Msg_Arg_SDDatInType_Len                     1
`define     Msg_Arg_SDDatInType_Range                   50:50
`define     Msg_Arg_SDDatInType_0                       `Msg_Arg_SDDatInType_Len'b0
`define     Msg_Arg_SDDatInType_512                     `Msg_Arg_SDDatInType_Len'b1
`define     Msg_Arg_SDCmd_Range                         47:0

`define Msg_Type_SDDatOut                               `Msg_Type_Len'h03

`define Msg_Type_SDGetStatus                            `Msg_Type_Len'h04
`define     Resp_Arg_SDCmdDone_Range                    63:63
`define     Resp_Arg_SDRespDone_Range                   62:62
`define         Resp_Arg_SDRespCRCErr_Range             61:61
`define         Resp_Arg_SDResp_Range                   60:13
`define         Resp_Arg_SDResp_Len                     48
`define     Resp_Arg_SDDatOutDone_Range                 12:12
`define         Resp_Arg_SDDatOutCRCErr_Range           11:11
`define     Resp_Arg_SDDatInDone_Range                  10:10
`define         Resp_Arg_SDDatInCRCErr_Range            9:9
`define         Resp_Arg_SDDatInCMD6AccessMode_Range    8:5
`define     Resp_Arg_SDDat0Idle_Range                   4:4
`define     Resp_Arg_SDFiller_Range                     3:0

`define Msg_Type_SDAbort                                `Msg_Type_Len'h05
`define Msg_Type_NoOp                                   `Msg_Type_Len'hFF

module Top(
    input wire          clk24mhz,
    
    input wire          ctrl_clk,
    input wire          ctrl_rst,
    input wire          ctrl_di,
    output wire         ctrl_do,
    
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
    
    // output reg[3:0]    led = 0
);
    // ====================
    // Shared Nets/Registers
    // ====================
    wire ctrl_rst_;
    wire ctrl_din;
    reg[`Msg_Len-1:0] ctrl_dinReg = 0;
    wire[`Msg_Type_Len-1:0] ctrl_msgType = ctrl_dinReg[`Msg_Type_Range];
    wire[`Msg_Arg_Len-1:0] ctrl_msgArg = ctrl_dinReg[`Msg_Arg_Range];
    reg[`Msg_Arg_SDRespType_Len-1:0] ctrl_sdRespType = 0;
    reg[`Msg_Arg_SDDatInType_Len-1:0] ctrl_sdDatInType = 0;
    reg[47:0] ctrl_sdCmd = 0;
    
    `TogglePulse(w_sdDatOutTrigger, ctrl_sdDatOutTrigger, posedge, w_clk);
    `TogglePulse(sd_cmdOutTrigger, ctrl_sdCmdOutTrigger, posedge, sd_clk_int);
    `ToggleAck(sd_abort, sd_abortAck, ctrl_sdAbort, posedge, sd_clk_int);
    
    `ToggleAck(ctrl_sdCmdDone_, ctrl_sdCmdDoneAck, sd_cmdDone, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdRespDone_, ctrl_sdRespDoneAck, sd_respDone, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatOutDone_, ctrl_sdDatOutDoneAck, sd_datOutDone, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatInDone_, ctrl_sdDatInDoneAck, sd_datInDone, posedge, ctrl_clk);
    
    `Sync(ctrl_sdDat0Idle, sd_dat0Idle, posedge, ctrl_clk);
    
    
    
    // // ====================
    // // Fast Clock (207 MHz)
    // // ====================
    // localparam ClkFastFreq = 207_000_000;
    // wire clkFast;
    // ClockGen #(
    //     .FREQ(ClkFastFreq),
    //     .DIVR(1),
    //     .DIVF(68),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen_clkFast(.clkRef(clk24mhz), .clk(clkFast));
    
    // // ====================
    // // Fast Clock (144 MHz)
    // // ====================
    // localparam ClkFastFreq = 144_000_000;
    // wire clkFast;
    // ClockGen #(
    //     .FREQ(ClkFastFreq),
    //     .DIVR(0),
    //     .DIVF(23),
    //     .DIVQ(2),
    //     .FILTER_RANGE(2)
    // ) ClockGen_clkFast(.clkRef(clk24mhz), .clk(clkFast));
    
    // // ====================
    // // Fast Clock (162 MHz)
    // // ====================
    // localparam ClkFastFreq = 162_000_000;
    // wire clkFast;
    // ClockGen #(
    //     .FREQ(ClkFastFreq),
    //     .DIVR(0),
    //     .DIVF(26),
    //     .DIVQ(2),
    //     .FILTER_RANGE(2)
    // ) ClockGen_clkFast(.clkRef(clk24mhz), .clk(clkFast));
    
    // // ====================
    // // Fast Clock (192 MHz)
    // // ====================
    // localparam ClkFastFreq = 192_000_000;
    // wire clkFast;
    // ClockGen #(
    //     .FREQ(ClkFastFreq),
    //     .DIVR(0),
    //     .DIVF(63),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen_clkFast(.clkRef(clk24mhz), .clk(clkFast));
    
    
    // ====================
    // Fast Clock (120 MHz)
    // ====================
    localparam ClkFastFreq = 120_000_000;
    wire clkFast;
    ClockGen #(
        .FREQ(ClkFastFreq),
        .DIVR(0),
        .DIVF(39),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen_clkFast(.clkRef(clk24mhz), .clk(clkFast));
    
    // // ====================
    // // Fast Clock (48 MHz)
    // // ====================
    // localparam ClkFastFreq = 48_000_000;
    // wire clkFast;
    // ClockGen #(
    //     .FREQ(ClkFastFreq),
    //     .DIVR(0),
    //     .DIVF(31),
    //     .DIVQ(4),
    //     .FILTER_RANGE(2)
    // ) ClockGen_clkFast(.clkRef(clk24mhz), .clk(clkFast));
    
    // ====================
    // Slow Clock (400 kHz)
    // ====================
    localparam ClkSlowFreq = 400000;
    localparam ClkSlowDividerWidth = $clog2(DivCeil(ClkFastFreq, ClkSlowFreq));
    reg[ClkSlowDividerWidth-1:0] clkSlowDivider = 0;
    wire clkSlow = clkSlowDivider[ClkSlowDividerWidth-1];
    always @(posedge clkFast) begin
        clkSlowDivider <= clkSlowDivider+1;
    end
    
    // ====================
    // sd_clk_int
    // ====================
    `Sync(sd_clkSlow, ctrl_sdClkSlow, negedge, clkSlow);
    `Sync(sd_clkFast, ctrl_sdClkFast, negedge, clkFast);
    wire sd_clk_int = (sd_clkSlow ? clkSlow : (sd_clkFast ? clkFast : 0));
    // wire sd_clk_int = clkFast;
    
    // ====================
    // sd_clk / sd_clkDelay
    //   Delay `sd_clk` relative to `sd_clk_int` to correct the phase from the SD card's perspective
    //   `sd_clkDelay` should only be set while `sd_clk_int` is stopped
    // ====================
    localparam SDClkDelayCount = 16;
    reg[$clog2(SDClkDelayCount)-1:0] sd_clkDelay = 0;
    
    // Delay #(
    //     .Count(0)
    // ) Delay_sd_clk_int(
    //     .in(sd_clk_int),
    //     .out(sd_clk)
    // );
    
    VariableDelay #(
        .Count(SDClkDelayCount)
    ) VariableDelay_sd_clk_int(
        .in(sd_clk_int),
        .sel(sd_clkDelay),
        .out(sd_clk)
    );
    
    // ====================
    // w_clk
    // ====================
    wire w_clk = clkSlowDivider[0];
    
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
    always @(posedge w_clk) begin
        case (w_state)
        0: begin
            w_sdDatOutFifo_wdata <= 0;
            // w_sdDatOutFifo_wdata <= 16'hFFFF;
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
            if (w_counter === 'hA00-2) begin
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
    reg[2:0] sd_cmdOutActive = 0; // 3 bits -- see explanation where assigned
    reg[5:0] sd_cmdOutCounter = 0;
    wire sd_cmdIn;
    wire sd_cmdOutCRC;
    
    reg[7:0] sd_respCounter = 0;
    reg sd_respCRCEn = 0;
    reg sd_respTrigger = 0;
    reg sd_respCRCErr = 0;
    reg sd_respStaged = 0;
    reg[47:0] sd_resp = 0;
    wire sd_respCRC;
    
    reg[3:0] sd_datOutState = 0;
    reg[2:0] sd_datOutActive = 0; // 3 bits -- see explanation where assigned
    reg sd_datOutCRCEn = 0;
    reg sd_datOutCRCErr = 0;
    reg sd_datOutCRCOutEn = 0;
    reg sd_datOutEndBit = 0;
    reg sd_datOutEnding = 0;
    reg sd_datOutPrevBank = 0;
    reg sd_datOutStartBit = 0;
    reg[19:0] sd_datOutReg = 0;
    reg[1:0] sd_datOutCounter = 0;
    reg[3:0] sd_datOutCRCCounter = 0;
    wire[3:0] sd_datOutCRC;
    wire[4:0] sd_datOutCRCStatus = {sd_datInReg[16], sd_datInReg[12], sd_datInReg[8], sd_datInReg[4], sd_datInReg[0]};
    wire sd_datOutCRCStatusOK = sd_datOutCRCStatus===5'b0_010_1; // 5 bits: start bit, CRC status, end bit
    reg sd_datOutCRCStatusOKReg = 0;
    
    reg[4:0] sd_datInState = 0;
    reg sd_datInStateInit = 0;
    reg sd_datInTrigger = 0;
    wire[3:0] sd_datIn;
    reg[19:0] sd_datInReg = 0;
    reg sd_datInCRCEn = 0;
    wire[3:0] sd_datInCRC;
    reg sd_datInCRCErr = 0;
    reg[6:0] sd_datInCounter = 0;
    reg[3:0] sd_datInCRCCounter = 0;
    
    reg[3:0] sd_datInCMD6AccessMode = 0;
    
    always @(posedge sd_clk_int) begin
        sd_cmdOutState <= sd_cmdOutState<<1|!sd_cmdOutStateInit|sd_cmdOutState[$size(sd_cmdOutState)-1];
        sd_cmdOutStateInit <= 1;
        sd_cmdOutCounter <= sd_cmdOutCounter-1;
        // `sd_cmdOutActive` is 3 bits to track whether `sd_cmdIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        sd_cmdOutActive <= (sd_cmdOutActive<<1)|sd_cmdOutActive[0];
        
        sd_cmdRespShiftReg <= sd_cmdRespShiftReg<<1|sd_respStaged;
        if (sd_cmdOutCRCOutEn)  sd_cmdRespShiftReg[47] <= sd_cmdOutCRC;
        
        sd_respState <= sd_respState<<1|!sd_respStateInit|sd_respState[$size(sd_respState)-1];
        sd_respStateInit <= 1;
        sd_respStaged <= sd_cmdOutActive[2] ? 1'b1 : sd_cmdIn;
        sd_respCounter <= sd_respCounter-1;
        
        sd_datOutCounter <= sd_datOutCounter-1;
        sd_datOutCRCCounter <= sd_datOutCRCCounter-1;
        sd_datOutFifo_rtrigger <= 0; // Pulse
        sd_datOutPrevBank <= sd_datOutFifo_rbank;
        sd_datOutEnding <= sd_datOutEnding|(sd_datOutPrevBank && !sd_datOutFifo_rbank);
        sd_datOutStartBit <= 0; // Pulse
        sd_datOutEndBit <= 0; // Pulse
        sd_datOutCRCStatusOKReg <= sd_datOutCRCStatusOK;
        sd_datOutReg <= sd_datOutReg<<4;
        if (!sd_datOutCounter)  sd_datOutReg[15:0] <= sd_datOutFifo_rdata;
        if (sd_datOutCRCOutEn)  sd_datOutReg[19:16] <= sd_datOutCRC;
        if (sd_datOutStartBit)  sd_datOutReg[19:16] <= 4'b0000;
        if (sd_datOutEndBit)    sd_datOutReg[19:16] <= 4'b1111;
        
        // `sd_datOutActive` is 3 bits to track whether `sd_datIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        sd_datOutActive <= (sd_datOutActive<<1)|sd_datOutActive[0];
        
        sd_datInState <= sd_datInState<<1|!sd_datInStateInit|sd_datInState[$size(sd_datInState)-1];
        sd_datInStateInit <= 1;
        sd_datInReg <= (sd_datInReg<<4)|(sd_datOutActive[2] ? 4'b1111 : {sd_datIn[3], sd_datIn[2], sd_datIn[1], sd_datIn[0]});
        sd_datInCounter <= sd_datInCounter-1;
        sd_datInCRCCounter <= sd_datInCRCCounter-1;
        sd_dat0Idle <= sd_datInReg[0];
        
        // ====================
        // CmdOut State Machine
        // ====================
        if (sd_cmdOutState[0]) begin
            sd_cmdOutActive[0] <= 0;
            sd_cmdOutCounter <= 38;
            if (sd_cmdOutTrigger) begin
                $display("[SD-CTRL:CMDOUT] Command to be clocked out: %b", ctrl_msgArg[47:0]);
                // Clear outstanding abort when starting a new command
                if (sd_abort) sd_abortAck <= !sd_abortAck;
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
            sd_cmdDone <= !sd_cmdDone;
            sd_respTrigger <= (ctrl_sdRespType !== `Msg_Arg_SDRespType_0);
            sd_datInTrigger <= (ctrl_sdDatInType !== `Msg_Arg_SDDatInType_0);
        end
        
        
        
        
        // ====================
        // Resp State Machine
        // ====================
        if (sd_respState[0]) begin
            sd_respCRCEn <= 0;
            // We're accessing `ctrl_sdRespType` without synchronization, but that's
            // safe because the ctrl_ domain isn't allowed to modify it until we
            // signal `sd_respDone`
            sd_respCounter <= (ctrl_sdRespType[`Msg_Arg_SDRespType_48_Range] ? 48 : 136) - 8;
            
            // Handle being aborted
            if (sd_abort) begin
                sd_respTrigger <= 0;
                // Signal that we're done
                // Only do this if `sd_respTrigger`=1 though, otherwise toggling `sd_respDone`
                // will toggle us from Done->!Done, instead of remaining Done.
                if (sd_respTrigger) sd_respDone <= !sd_respDone;
                
                // Stay in this state
                sd_respState[1:0] <= sd_respState[1:0];
            
            end else if (sd_respTrigger && !sd_respStaged) begin
                $display("[SD-CTRL:RESP] Triggered");
                sd_respTrigger <= 0;
                sd_respCRCErr <= 0;
                sd_respCRCEn <= 1;
            
            end else begin
                // Stay in this state
                sd_respState[1:0] <= sd_respState[1:0];
            end
        end
        
        if (sd_respState[1]) begin
            if (!sd_respCounter) begin
                sd_respCRCEn <= 0;
            end else begin
                sd_respState[2:1] <= sd_respState[2:1];
            end
        end
        
        if (sd_respState[8:2]) begin
            if (sd_respCRC === sd_cmdRespShiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good CRC bit (ours: %b, theirs: %b) ✅", sd_respCRC, sd_cmdRespShiftReg[1]);
            end else begin
                $display("[SD-CTRL:RESP] Response: Bad CRC bit (ours: %b, theirs: %b) ❌", sd_respCRC, sd_cmdRespShiftReg[1]);
                sd_respCRCErr <= 1;
            end
        end
        
        if (sd_respState[9]) begin
            if (sd_cmdRespShiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good end bit ✅");
            end else begin
                $display("[SD-CTRL:RESP] Response: Bad end bit ❌");
                sd_respCRCErr <= 1;
            end
            
            // Ideally we'd assign `sd_resp` on the previous clock cycle
            // so that we didn't need this right-shift, but that hurts
            // our perf quite a bit. So since the high bit of SD card
            // commands/responses is always zero, assign it here.
            sd_resp <= sd_cmdRespShiftReg>>1;
            // Signal that the response was received
            sd_respDone <= !sd_respDone;
        end
        
        
        
        
        // ====================
        // DatOut State Machine
        // ====================
        case (sd_datOutState)
        0: begin
            if (sd_datOutFifo_rok) begin
                $display("[SD-CTRL:DATOUT] Write session starting");
                sd_datOutCRCErr <= 0;
                sd_datOutState <= 1;
            end
        end
        
        1: begin
            $display("[SD-CTRL:DATOUT] Write another block");
            sd_datOutCounter <= 0;
            sd_datOutCRCCounter <= 0;
            sd_datOutActive[0] <= 0;
            sd_datOutEnding <= 0;
            sd_datOutCRCEn <= 0;
            sd_datOutStartBit <= 1;
            sd_datOutState <= 2;
        end
        
        2: begin
            sd_datOutActive[0] <= 1;
            sd_datOutCRCEn <= 1;
            
            if (!sd_datOutCounter) begin
                // $display("[SD-CTRL:DATOUT]   Write another word: %x", sd_datOutFifo_rdata);
                sd_datOutFifo_rtrigger <= 1;
            end
            
            if (sd_datOutEnding) begin
                $display("[SD-CTRL:DATOUT] Done writing");
                sd_datOutState <= 3;
            end
        end
        
        // Wait for CRC to be clocked out and supply end bit
        3: begin
            sd_datOutCRCOutEn <= 1;
            sd_datOutState <= 4;
        end
        
        4: begin
            if (!sd_datOutCRCCounter) begin
                sd_datOutCRCEn <= 0;
                sd_datOutEndBit <= 1;
                sd_datOutState <= 5;
            end
        end
        
        // Disable DatOut when we finish outputting the CRC,
        // and wait for the CRC status from the card.
        5: begin
            sd_datOutCRCOutEn <= 0;
            if (sd_datOutCRCCounter === 14) begin
                sd_datOutActive[0] <= 0;
            end
            
            // SD response timeout point:
            //   check if we've been aborted before checking SD response
            if (sd_abort) begin
                sd_datOutState <= 8;
            
            end else if (!sd_datInReg[16]) begin
                sd_datOutState <= 6;
            end
        end
        
        // Check CRC status token
        6: begin
            $display("[SD-CTRL:DATOUT] DatOut: sd_datOutCRCStatusOKReg: %b", sd_datOutCRCStatusOKReg);
            // 5 bits: start bit, CRC status, end bit
            if (sd_datOutCRCStatusOKReg) begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status valid ✅");
            end else begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status invalid: %b ❌", sd_datOutCRCStatusOKReg);
                sd_datOutCRCErr <= 1;
            end
            sd_datOutState <= 7;
        end
        
        // Wait until the card stops being busy (busy == DAT0 low)
        7: begin
            // SD response timeout point:
            //   check if we've been aborted before checking SD response
            if (sd_abort) begin
                sd_datOutState <= 8;
            
            end else if (sd_datInReg[0]) begin
                $display("[SD-CTRL:DATOUT] Card ready");
                
                if (sd_datOutFifo_rok) begin
                    sd_datOutState <= 1;
                
                end else begin
                    // Signal that DatOut is done
                    sd_datOutDone <= !sd_datOutDone;
                    sd_datOutState <= 0;
                end
            
            end else begin
                $display("[SD-CTRL:DATOUT] Card busy");
            end
        end
        
        // Abort state:
        //   Drain the fifo, and once it's empty, signal that
        //   we're done and go back to state 0.
        8: begin
            // Disable DatOut while we're aborting
            sd_datOutActive[0] <= 0;
            
            // Drain only on !sd_datOutCounter (the same as DatOut does normally)
            // so that we don't read too fast. If we read faster than we write,
            // then `!sd_datOutFifo_rok`=1, and we'll signal that we're done and
            // transition to state 0 before we're actually done.
            if (!sd_datOutCounter) begin
                sd_datOutFifo_rtrigger <= 1;
            end
            
            if (!sd_datOutFifo_rok) begin
                // Signal that DatOut is done
                sd_datOutDone <= !sd_datOutDone;
                sd_datOutState <= 0;
            end
        end
        endcase
        
        
        
        
        
        // ====================
        // DatIn State Machine
        // ====================
        if (sd_datInState[0]) begin
            sd_datInCounter <= 127;
            sd_datInCRCEn <= 0;
            
            if (sd_abort) begin
                sd_datInTrigger <= 0;
                
                // Signal that we're done
                // Only do this if `sd_datInTrigger`=1 though, otherwise toggling `sd_datInDone`
                // will toggle us from Done->!Done, instead of remaining Done.
                if (sd_datInTrigger) sd_datInDone <= !sd_datInDone;
                
                // Stay in this state
                sd_datInState[1:0] <= sd_datInState[1:0];
            
            end else if (sd_datInTrigger && !sd_datInReg[0]) begin
                $display("[SD-CTRL:DATIN] Triggered");
                sd_datInTrigger <= 0;
                sd_datInCRCErr <= 0;
                sd_datInCRCEn <= 1;
            
            end else begin
                // Stay in this state
                sd_datInState[1:0] <= sd_datInState[1:0];
            end
        end
        
        if (sd_datInState[1]) begin
            // Stash the access mode from the DatIn response.
            // (This assumes we're receiving a CMD6 response.)
            if (sd_datInCounter === 7'd94) begin
                sd_datInCMD6AccessMode <= sd_datInReg[3:0];
            end
            
            if (!sd_datInCounter) begin
                sd_datInCRCEn <= 0;
            end
            
            // Stay in this state until sd_datInCounter==0
            if (sd_datInCounter) begin
                sd_datInState[2:1] <= sd_datInState[2:1];
            end
        end
        
        if (sd_datInState[2]) begin
            sd_datInCRCCounter <= 15;
        end
        
        if (sd_datInState[3]) begin
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
                $display("[SD-CTRL:DATIN] Bad end bit ❌");
                sd_datInCRCErr <= 1;
            end
            // Signal that the DatIn is complete
            sd_datInDone <= !sd_datInDone;
        end
    end
    
    
    
    
    
    
    // ====================
    // Control State Machine
    // ====================
    reg[1:0] ctrl_state = 0;
    reg[6:0] ctrl_counter = 0;
    // +5 for delay states, so that clients send an extra byte before receiving the response
    reg[`Resp_Len+5-1:0] ctrl_doutReg = 0;
    
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
                // $display("[CTRL] Got command: %b [cmd: %0d, arg: %0d]", ctrl_dinReg, ctrl_msgType, ctrl_msgArg);
                case (ctrl_msgType)
                // Echo
                `Msg_Type_Echo: begin
                    $display("[CTRL] Got Msg_Type_Echo: %0h", ctrl_msgArg);
                    ctrl_doutReg[`Resp_Arg_Range] <= {ctrl_msgArg, 8'h00};
                    // ctrl_doutReg[`Resp_Arg_Range] <= 'b10000;
                end
                
                // Set SD clock source
                `Msg_Type_SDClkSet: begin
                    $display("[CTRL] Got Msg_Type_SDClkSet: delay=%0d fast=%b slow=%b",
                        ctrl_msgArg[`Msg_Arg_SDClkDelay_Range],
                        ctrl_msgArg[`Msg_Arg_SDClkSrc_Fast_Range],
                        ctrl_msgArg[`Msg_Arg_SDClkSrc_Slow_Range]);
                    
                    // We don't need to synchronize `sd_clkDelay` into the sd_ domain,
                    // because it should only be set while the sd_ clock is disabled.
                    sd_clkDelay <= ctrl_msgArg[`Msg_Arg_SDClkDelay_Range];
                    ctrl_sdClkFast <= ctrl_msgArg[`Msg_Arg_SDClkSrc_Fast_Range];
                    ctrl_sdClkSlow <= ctrl_msgArg[`Msg_Arg_SDClkSrc_Slow_Range];
                end
                
                // Clock out SD command
                `Msg_Type_SDSendCmd: begin
                    $display("[CTRL] Got Msg_Type_SDSendCmd");
                    // Clear our signals so they can be reliably observed via SDGetStatus
                    if (!ctrl_sdCmdDone_) ctrl_sdCmdDoneAck <= !ctrl_sdCmdDoneAck;
                    
                    // Reset `ctrl_sdRespDone_` if the Resp state machine will run
                    if (ctrl_msgArg[`Msg_Arg_SDRespType_Range] !== `Msg_Arg_SDRespType_0) begin
                        if (!ctrl_sdRespDone_) ctrl_sdRespDoneAck <= !ctrl_sdRespDoneAck;
                    end
                    
                    // Reset `ctrl_sdDatInDone_` if the DatIn state machine will run
                    if (ctrl_msgArg[`Msg_Arg_SDDatInType_Range] !== `Msg_Arg_SDDatInType_0) begin
                        if (!ctrl_sdDatInDone_) ctrl_sdDatInDoneAck <= !ctrl_sdDatInDoneAck;
                    end
                    
                    ctrl_sdRespType <= ctrl_msgArg[`Msg_Arg_SDRespType_Range];
                    ctrl_sdDatInType <= ctrl_msgArg[`Msg_Arg_SDDatInType_Range];
                    ctrl_sdCmd <= ctrl_msgArg[`Msg_Arg_SDCmd_Range];
                    ctrl_sdCmdOutTrigger <= !ctrl_sdCmdOutTrigger;
                end
                
                `Msg_Type_SDDatOut: begin
                    $display("[CTRL] Got Msg_Type_SDDatOut");
                    if (!ctrl_sdDatOutDone_) ctrl_sdDatOutDoneAck <= !ctrl_sdDatOutDoneAck;
                    ctrl_sdDatOutTrigger <= !ctrl_sdDatOutTrigger;
                end
                
                // Get SD status / response
                `Msg_Type_SDGetStatus: begin
                    $display("[CTRL] Got Msg_Type_SDGetStatus");
                    
                    ctrl_doutReg[`Resp_Arg_SDCmdDone_Range] <= !ctrl_sdCmdDone_;
                    ctrl_doutReg[`Resp_Arg_SDRespDone_Range] <= !ctrl_sdRespDone_;
                        ctrl_doutReg[`Resp_Arg_SDRespCRCErr_Range] <= sd_respCRCErr;
                    ctrl_doutReg[`Resp_Arg_SDDatOutDone_Range] <= !ctrl_sdDatOutDone_;
                        ctrl_doutReg[`Resp_Arg_SDDatOutCRCErr_Range] <= sd_datOutCRCErr;
                    ctrl_doutReg[`Resp_Arg_SDDatInDone_Range] <= !ctrl_sdDatInDone_;
                        ctrl_doutReg[`Resp_Arg_SDDatInCRCErr_Range] <= sd_datInCRCErr;
                        ctrl_doutReg[`Resp_Arg_SDDatInCMD6AccessMode_Range] <= sd_datInCMD6AccessMode;
                    ctrl_doutReg[`Resp_Arg_SDDat0Idle_Range] <= ctrl_sdDat0Idle;
                    ctrl_doutReg[`Resp_Arg_SDResp_Range] <= sd_resp;
                end
                
                `Msg_Type_SDAbort: begin
                    $display("[CTRL] Got Msg_Type_SDAbort");
                    ctrl_sdAbort <= !ctrl_sdAbort;
                end
                
                `Msg_Type_NoOp: begin
                    $display("[CTRL] Got Msg_Type_None");
                end
                
                default: begin
                    $display("[CTRL] BAD COMMAND: %0d ❌", ctrl_msgType);
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
    
    reg         ctrl_clk;
    reg         ctrl_rst;
    tri1        ctrl_di;
    tri1        ctrl_do;
    
    wire        sd_clk;
    tri1        sd_cmd;
    tri1[3:0]   sd_dat;
    wire[3:0]   led;
    
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
    
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        ctrl_rst = 0;
        #1; // Let `ctrl_rst` change take effect
            ctrl_diReg = {typ, arg};
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
    
    task SendMsgResp(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        SendMsg(typ, arg);
        
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
    end endtask
    
    task SendSDCmd(input[5:0] sdCmd, input[`Msg_Arg_SDRespType_Len-1:0] respType, input[`Msg_Arg_SDDatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg[`Msg_Arg_Len-1] arg;
        arg = 0;
        arg[`Msg_Arg_SDRespType_Range] = respType;
        arg[`Msg_Arg_SDDatInType_Range] = datInType;
        arg[`Msg_Arg_SDCmd_Range] = {2'b01, sdCmd, sdArg, 7'b0, 1'b1};
        
        SendMsg(`Msg_Type_SDSendCmd, arg);
    end endtask
    
    task SendSDCmdResp(input[5:0] sdCmd, input[`Msg_Arg_SDRespType_Len-1:0] respType, input[`Msg_Arg_SDDatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg done;
        SendSDCmd(sdCmd, respType, datInType, sdArg);
        
        // Wait for SD command to be sent
        do begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            
            // If a response is expected, we're done when the response is received
            if (respType !== `Msg_Arg_SDRespType_0) done = resp[`Resp_Arg_SDRespDone_Range];
            // If a response isn't expected, we're done when the command is sent
            else done = resp[`Resp_Arg_SDCmdDone_Range];
        end while(!done);
    end endtask
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        reg[`Resp_Arg_SDResp_Len-1:0] sdResp;
        
        // Set our initial state
        ctrl_clk = 0;
        ctrl_rst = 1;
        ctrl_diReg = ~0;
        #1;
        
        // // ====================
        // // Test NoOp command
        // // ====================
        //
        // SendMsgResp(`Msg_Type_NoOp, 56'h66554433221100);
        // $display("Got response: %h", resp);
        // `Finish;
        
        
        
        
        
        // // ====================
        // // Test Echo command
        // // ====================
        //
        // SendMsgResp(`Msg_Type_Echo, `Msg_Arg_Len'h66554433221100);
        // $display("Got response: %h", resp);
        // `Finish;
        
        
        
        

        // // ====================
        // // Test SD CMD8 (SEND_IF_COND)
        // // ====================
        //
        // // Set SD clock source = slow clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_Slow);
        //
        // // Send SD CMD0
        // SendSDCmdResp(CMD0, `Msg_Arg_SDRespType_0, `Msg_Arg_SDDatInType_0, 0);
        //
        // // Send SD CMD8
        // SendSDCmdResp(CMD8, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_0, 32'h000001AA);
        // if (resp[`Resp_Arg_SDRespCRCErr_Range] !== 1'b0) begin
        //     $display("[EXT] CRC error ❌");
        //     `Finish;
        // end
        //
        // sdResp = resp[`Resp_Arg_SDResp_Range];
        // if (sdResp[15:8] !== 8'hAA) begin
        //     $display("[EXT] Bad response: %h ❌", resp);
        //     `Finish;
        // end
        //
        // `Finish;
        
        
        
        
        
        // // ====================
        // // Test writing data to SD card / DatOut
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_Fast);
        //
        // // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        // SendSDCmdResp(CMD55, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_0, 32'b0);
        // SendSDCmdResp(ACMD23, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_0, 32'b1);
        //
        // // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        // SendSDCmdResp(CMD25, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_0, 32'b0);
        //
        // // Clock out data on DAT lines
        // SendMsg(`Msg_Type_SDDatOut, 0);
        //
        // // Wait until we're done clocking out data on DAT lines
        // $display("[EXT] Waiting while data is written...");
        // do begin
        //     // Request SD status
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        // end while(!resp[`Resp_Arg_SDDatOutDone_Range]);
        // $display("[EXT] Done writing (SD resp: %b)", resp[`Resp_Arg_SDResp_Range]);
        //
        // // Check CRC status
        // if (resp[`Resp_Arg_SDDatOutCRCErr_Range] === 1'b0) begin
        //     $display("[EXT] DatOut CRC OK ✅");
        // end else begin
        //     $display("[EXT] DatOut CRC bad ❌");
        // end
        // `Finish;

        
        
        
        
        
        
        
        
        
        // // ====================
        // // Test CMD6 (SWITCH_FUNC) + DatIn
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_Fast);
        //
        // // Send SD command CMD6 (SWITCH_FUNC)
        // SendSDCmdResp(CMD6, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_512, 32'h80FFFFF3);
        // $display("[EXT] Waiting for DatIn to complete...");
        // do begin
        //     // Request SD status
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        // end while(!resp[`Resp_Arg_SDDatInDone_Range]);
        // $display("[EXT] DatIn completed");
        //
        // // Check DatIn CRC status
        // if (resp[`Resp_Arg_SDDatInCRCErr_Range] === 1'b0) begin
        //     $display("[EXT] DatIn CRC OK ✅");
        // end else begin
        //     $display("[EXT] DatIn CRC bad ❌");
        // end
        //
        // // Check the access mode from the CMD6 response
        // if (resp[`Resp_Arg_SDDatInCMD6AccessMode_Range] === 4'h3) begin
        //     $display("[EXT] CMD6 access mode == 0x3 ✅");
        // end else begin
        //     $display("[EXT] CMD6 access mode == 0x%h ❌", resp[`Resp_Arg_SDDatInCMD6AccessMode_Range]);
        // end
        // `Finish;
        
        
        
        
        
        
        
        // // ====================
        // // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
        // //   Note: we expect CRC errors in the response because the R2
        // //   response CRC doesn't follow the semantics of other responses
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_None);
        //
        // // Set SD clock source = slow clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_Slow);
        //
        // // Send SD command CMD2 (ALL_SEND_CID)
        // SendSDCmdResp(CMD2, `Msg_Arg_SDRespType_136, `Msg_Arg_SDDatInType_0, 0);
        // $display("====================================================");
        // $display("^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        // $display("====================================================");
        
        
        
        
        
        
        
        
        
        
        // // ====================
        // // Test Resp abort
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_Fast);
        //
        // // Send an SD command that doesn't provide a response
        // SendSDCmd(CMD0, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_0, 0);
        // $display("[EXT] Verifying that Resp times out...");
        // done = 0;
        // for (i=0; i<10 && !done; i++) begin
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //     $display("[EXT] Pre-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //         i+1,
        //         resp[`Resp_Arg_SDCmdDone_Range],
        //         resp[`Resp_Arg_SDRespDone_Range],
        //         resp[`Resp_Arg_SDDatOutDone_Range],
        //         resp[`Resp_Arg_SDDatInDone_Range]);
        //
        //     done = resp[`Resp_Arg_SDRespDone_Range];
        // end
        //
        // if (!done) begin
        //     $display("[EXT] Resp timeout ✅");
        //     $display("[EXT] Aborting...");
        //     SendMsg(`Msg_Type_SDAbort, 0);
        //
        //     $display("[EXT] Checking abort status...");
        //     done = 0;
        //     for (i=0; i<10 && !done; i++) begin
        //         SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //         $display("[EXT] Post-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //             i+1,
        //             resp[`Resp_Arg_SDCmdDone_Range],
        //             resp[`Resp_Arg_SDRespDone_Range],
        //             resp[`Resp_Arg_SDDatOutDone_Range],
        //             resp[`Resp_Arg_SDDatInDone_Range]);
        //
        //         done =  resp[`Resp_Arg_SDCmdDone_Range]     &&
        //                 resp[`Resp_Arg_SDRespDone_Range]    &&
        //                 resp[`Resp_Arg_SDDatOutDone_Range]  &&
        //                 resp[`Resp_Arg_SDDatInDone_Range]   ;
        //     end
        //
        //     if (done) begin
        //         $display("[EXT] Abort OK ✅");
        //     end else begin
        //         $display("[EXT] Abort failed ❌");
        //     end
        //
        // end else begin
        //     $display("[EXT] DatIn didn't timeout? ❌");
        // end
        // `Finish;
        
        
        
        
        
        
        
        
        // ====================
        // Test DatOut abort
        // ====================

        // Disable SD clock
        SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_None);

        // Set SD clock source = fast clock
        SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_Fast);

        // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        SendSDCmdResp(CMD25, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_0, 32'b0);

        // Clock out data on DAT lines
        SendMsg(`Msg_Type_SDDatOut, 0);

        // Verify that we timeout
        $display("[EXT] Verifying that DatOut times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            $display("[EXT] Pre-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                resp[`Resp_Arg_SDCmdDone_Range],
                resp[`Resp_Arg_SDRespDone_Range],
                resp[`Resp_Arg_SDDatOutDone_Range],
                resp[`Resp_Arg_SDDatInDone_Range]);

            done = resp[`Resp_Arg_SDDatOutDone_Range];
        end

        if (!done) begin
            $display("[EXT] DatOut timeout ✅");
            $display("[EXT] Aborting...");
            SendMsg(`Msg_Type_SDAbort, 0);

            $display("[EXT] Checking abort status...");
            done = 0;
            for (i=0; i<10 && !done; i++) begin
                SendMsgResp(`Msg_Type_SDGetStatus, 0);
                $display("[EXT] Post-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                    i+1,
                    resp[`Resp_Arg_SDCmdDone_Range],
                    resp[`Resp_Arg_SDRespDone_Range],
                    resp[`Resp_Arg_SDDatOutDone_Range],
                    resp[`Resp_Arg_SDDatInDone_Range]);

                done =  resp[`Resp_Arg_SDCmdDone_Range]     &&
                        resp[`Resp_Arg_SDRespDone_Range]    &&
                        resp[`Resp_Arg_SDDatOutDone_Range]  &&
                        resp[`Resp_Arg_SDDatInDone_Range]   ;
            end

            if (done) begin
                $display("[EXT] Abort OK ✅");
            end else begin
                $display("[EXT] Abort failed ❌");
            end

        end else begin
            $display("[EXT] DatOut didn't timeout? ❌");
        end
        // `Finish;
        
        
        
        
        
        
        
        
        // // ====================
        // // Test DatIn abort
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSrc_Fast);
        //
        // // Send SD command that doesn't respond on the DAT lines,
        // // but specify that we expect DAT data
        // SendSDCmdResp(CMD8, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_512, 0);
        // $display("[EXT] Verifying that DatIn times out...");
        // done = 0;
        // for (i=0; i<10 && !done; i++) begin
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //     $display("[EXT] Pre-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //         i+1,
        //         resp[`Resp_Arg_SDCmdDone_Range],
        //         resp[`Resp_Arg_SDRespDone_Range],
        //         resp[`Resp_Arg_SDDatOutDone_Range],
        //         resp[`Resp_Arg_SDDatInDone_Range]);
        //     done = resp[`Resp_Arg_SDDatInDone_Range];
        // end
        //
        // if (!done) begin
        //     $display("[EXT] DatIn timeout ✅");
        //     $display("[EXT] Aborting...");
        //     SendMsg(`Msg_Type_SDAbort, 0);
        //
        //     $display("[EXT] Checking abort status...");
        //     done = 0;
        //     for (i=0; i<10 && !done; i++) begin
        //         SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //         $display("[EXT] Post-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //             i+1,
        //             resp[`Resp_Arg_SDCmdDone_Range],
        //             resp[`Resp_Arg_SDRespDone_Range],
        //             resp[`Resp_Arg_SDDatOutDone_Range],
        //             resp[`Resp_Arg_SDDatInDone_Range]);
        //
        //         done =  resp[`Resp_Arg_SDCmdDone_Range]     &&
        //                 resp[`Resp_Arg_SDRespDone_Range]    &&
        //                 resp[`Resp_Arg_SDDatOutDone_Range]  &&
        //                 resp[`Resp_Arg_SDDatInDone_Range]   ;
        //     end
        //
        //     if (done) begin
        //         $display("[EXT] Abort OK ✅");
        //     end else begin
        //         $display("[EXT] Abort failed ❌");
        //     end
        //
        // end else begin
        //     $display("[EXT] DatIn didn't timeout? ❌");
        // end
        // `Finish;
    end
endmodule
`endif
