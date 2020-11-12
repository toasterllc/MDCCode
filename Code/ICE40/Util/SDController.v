// TODO: cmdOut -> cmd

module SDController #(
    parameter ClkFreq               = 120_000_000,
    parameter SDClkDelayWidth       = 4
)(
    input wire clk,
    
    output wire     sd_clk,
    inout wire      sd_cmd,
    inout wire[3:0] sd_dat,
    
    input wire          ctrl_sdClkSlow,
    input wire          ctrl_sdClkFast,
    input wire[47:0]    ctrl_sdCmd,
    input wire          ctrl_sdCmdOutTrigger,   // toggle
    input wire          ctrl_sdAbort,           // toggle
    
    input wire ctrl_sdRespType_48,
    input wire ctrl_sdRespType_136,
    input wire ctrl_sdDatInType_512,
    
    input wire[SDClkDelayWidth-1:0] sd_clkDelay,
    
    input wire datOutFIFO_writeClk,
    input wire datOutFIFO_writeTrigger,
    input wire[15:0] datOutFIFO_writeData,
    output wire datOutFIFO_writeOK,
    
    output reg sd_cmdDone = 0,          // toggle
    output reg sd_respDone = 0,         // toggle
    output reg sd_datOutDone = 0,       // toggle
    output reg sd_datInDone = 0,        // toggle
    output reg sd_dat0Idle = 0,         // level
    
    output reg[47:0]    sd_resp = 0,
    output reg          sd_respCRCErr = 0,
    output reg          sd_datOutCRCErr = 0,
    output reg          sd_datInCRCErr = 0,
    output reg[3:0]     sd_datInCMD6AccessMode = 0
);
    // ====================
    // Fast Clock (ClkFreq)
    // ====================
    localparam ClkFastFreq = ClkFreq;
    wire clkFast = clk;
    
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
    VariableDelay #(
        .Count(1<<SDClkDelayWidth)
    ) VariableDelay_sd_clk_int(
        .in(sd_clk_int),
        .sel(sd_clkDelay),
        .out(sd_clk)
    );
    
    `TogglePulse(sd_cmdOutTrigger, ctrl_sdCmdOutTrigger, posedge, sd_clk_int);
    `ToggleAck(sd_abort, sd_abortAck, ctrl_sdAbort, posedge, sd_clk_int);
    
    
    
    
    
    // ====================
    // SD Dat Out FIFO
    // ====================
    reg datOutFIFO_readTrigger = 0;
    wire[15:0] datOutFIFO_readData;
    wire datOutFIFO_readOK;
    wire datOutFIFO_readBank;
    BankFIFO #(
        .W(16),
        .N(8)
    ) BankFIFO(
        .w_clk(datOutFIFO_writeClk),
        .w_trigger(datOutFIFO_writeTrigger),
        .w_data(datOutFIFO_writeData),
        .w_ok(datOutFIFO_writeOK),
        
        .r_clk(sd_clk_int),
        .r_trigger(datOutFIFO_readTrigger),
        .r_data(datOutFIFO_readData),
        .r_ok(datOutFIFO_readOK),
        .r_bank(datOutFIFO_readBank)
    );
    
    
    
    
    
    
    
    
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
    reg sd_respStaged = 0;
    wire sd_respCRC;
    
    reg[3:0] sd_datOutState = 0;
    reg[2:0] sd_datOutActive = 0; // 3 bits -- see explanation where assigned
    reg sd_datOutCRCEn = 0;
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
    reg[6:0] sd_datInCounter = 0;
    reg[3:0] sd_datInCRCCounter = 0;
    
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
        datOutFIFO_readTrigger <= 0; // Pulse
        sd_datOutPrevBank <= datOutFIFO_readBank;
        sd_datOutEnding <= sd_datOutEnding|(sd_datOutPrevBank && !datOutFIFO_readBank);
        sd_datOutStartBit <= 0; // Pulse
        sd_datOutEndBit <= 0; // Pulse
        sd_datOutCRCStatusOKReg <= sd_datOutCRCStatusOK;
        sd_datOutReg <= sd_datOutReg<<4;
        if (!sd_datOutCounter)  sd_datOutReg[15:0] <= datOutFIFO_readData;
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
                $display("[SD-CTRL:CMDOUT] Command to be clocked out: %b", ctrl_sdCmd);
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
            sd_respTrigger <= (ctrl_sdRespType_48 || ctrl_sdRespType_136);
            sd_datInTrigger <= ctrl_sdDatInType_512;
        end
        
        
        
        
        // ====================
        // Resp State Machine
        // ====================
        if (sd_respState[0]) begin
            sd_respCRCEn <= 0;
            // We're accessing `ctrl_sdRespType` without synchronization, but that's
            // safe because the ctrl_ domain isn't allowed to modify it until we
            // signal `sd_respDone`
            sd_respCounter <= (ctrl_sdRespType_48 ? 48 : 136) - 8;
            
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
            if (datOutFIFO_readOK) begin
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
                // $display("[SD-CTRL:DATOUT]   Write another word: %x", datOutFIFO_readData);
                datOutFIFO_readTrigger <= 1;
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
                
                if (datOutFIFO_readOK) begin
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
            // then `!datOutFIFO_readOK`=1, and we'll signal that we're done and
            // transition to state 0 before we're actually done.
            if (!sd_datOutCounter) begin
                datOutFIFO_readTrigger <= 1;
            end
            
            if (!datOutFIFO_readOK) begin
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
