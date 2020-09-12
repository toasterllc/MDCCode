// Is there a minimum number of cycles after a command that we need to wait, before issuing another command?
//   Yes -- 8 cycles (N_CC)
//     -> Implemented
//
// Is there a minimum number of cycles after a response that we need to wait, before issuing another command?
//   Yes -- 8 cycles (N_RC)
//     -> Implemented
//
// For A2 cards: what procedure do we use to transition to 1.8V signaling?
//   Doing nothing doesn't work -- SD card doesn't use 1.8V signaling
//
// For non-A2 cards: what procedure do we use to transition to 1.8V signaling?
//   See Section 4.2.4 (SD-Init-ACMD41.pdf)
//
// TODO: What procedure do we use to transition to a faster clock?
//   "CMD6 function switching period is within 8 clocks after the end bit of status data. When CMD6 changes
//   the bus behavior (i.e. access mode), the host is allowed to use the new functions (increase/decrease
//   CLK frequency beyond the current max CLK frequency), at least 8 clocks after at the end of the switch
//   command transaction (see Figure 4-14)."
//
// TODO: handle never receiving a response from the card
//   according to 4.12.4 , the max number of cycles for a response to start is 64

// TODO: expose error state to clients
//   sit in the error state and wait for a power cycle?
//   or have the ability to clear the error and start over?

module SDCardInitializer(
    input wire          clk12mhz,
    output reg[15:0]    rca = 0,
    output reg          done = 0,
    
    // SDIO port
    output wire         sd_clk,
    input wire          sd_cmdIn,
    output wire         sd_cmdOut,
    output wire         sd_cmdOutActive,
    input wire[3:0]     sd_datIn
);
    // ====================
    // Internal clock (400 kHz)
    // ====================
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
    localparam ClkFreq = 400000;
    localparam ClkDividerWidth = $clog2(DivCeil(12000000, ClkFreq));
    reg[ClkDividerWidth-1:0] clkDivider = 0;
    wire clk = clkDivider[ClkDividerWidth-1];
    
    always @(posedge clk12mhz) begin
        clkDivider <= clkDivider-1;
    end
    
    
    
    
    
    // ====================
    // sd_clk
    // ====================
    assign sd_clk = clk && !clkEn_;
    
    
    
    
    // ====================
    // sd_cmd
    // ====================
    assign sd_cmdOut = cmdOutReg[47];
    assign sd_cmdOutActive = cmdOutActive;
    
    
    
    
    // ====================
    // State Machine Registers
    // ====================
    localparam DatInState_Idle  = 0;    // +0
    localparam DatInState_Go    = 1;    // +2
    localparam DatInState_Done  = 4;    // +0
    reg[3:0] datInState = 0;
    
    localparam StateInit        = 0;     // +18
    localparam StateCmdOut      = 19;    // +1
    localparam StateRespIn      = 21;    // +3
    localparam StateDelay       = 25;    // +0
    localparam StateError       = 26;    // +0
    reg[5:0] state = 0;
    reg[5:0] nextState = 0;
    
    localparam CMD0 =   6'd0;      // GO_IDLE_STATE
    localparam CMD2 =   6'd2;      // ALL_SEND_CID
    localparam CMD3 =   6'd3;      // SEND_RELATIVE_ADDR
    localparam CMD6 =   6'd6;      // SWITCH_FUNC
    localparam CMD7 =   6'd7;      // SELECT_CARD/DESELECT_CARD
    localparam CMD8 =   6'd8;      // SEND_IF_COND
    localparam CMD11 =  6'd11;     // VOLTAGE_SWITCH
    localparam CMD41 =  6'd41;     // SD_SEND_OP_COND
    localparam CMD55 =  6'd55;     // APP_CMD
    
    reg[6:0] respInExpectedCRC = 0;
    reg respCheckCRC = 0;
    
    localparam ClkDisableDelay = ((5*ClkFreq)/1000)-1;
    reg[10:0] delayCounter = 0;
    initial `assert(`fits(delayCounter, ClkDisableDelay));
    
    reg[47:0] cmdOutReg = 0;
    reg[7:0] cmdOutCounter = 0;
    reg cmdOutActive = 0;
    
    reg[135:0] cmdInReg = 0;
    reg[1:0] cmdInStaged = 0;
    reg cmdInActive = 0;
    reg[7:0] cmdInCounter = 0;
    
    reg[3:0] datInReg = 0;
    reg[7:0] datInCounter = 0;
    reg[3:0] datInCMD6FnGrp1 = 0;
    
    reg clkEn_ = 0;
    
    
    // ====================
    // CRC
    // ====================
    wire[6:0] cmdOutCRC;
    reg cmdOutCRCRst_ = 0;
    CRC7 crc1(
        .clk(clk),
        .rst_(cmdOutCRCRst_),
        .din(cmdOutReg[47]),
        .dout(cmdOutCRC)
    );
    
    wire[6:0] cmdInCRC;
    reg cmdInCRCRst_ = 0;
    CRC7 crc2(
        .clk(clk),
        .rst_(cmdInCRCRst_),
        .din(cmdInReg[0]),
        .dout(cmdInCRC)
    );
    
    
    
    
    
    
    // ====================
    // State Machine
    // ====================
    always @(posedge clk) begin
        cmdInStaged <= cmdInStaged<<1|sd_cmdIn;
        datInReg <= {sd_datIn[3], sd_datIn[2], sd_datIn[1], sd_datIn[0]};
    end
    
    always @(negedge clk) begin
        if (cmdOutActive) begin
            cmdOutReg <= cmdOutReg<<1;
            cmdOutCounter <= cmdOutCounter-1;
        end
        
        if (cmdInActive) begin
            cmdInReg <= (cmdInReg<<1)|cmdInStaged[1];
            cmdInCounter <= cmdInCounter-1;
        end
        
        datInCounter <= datInCounter-1;
        delayCounter <= delayCounter-1;
        
        
        
        
        
        
        
        
        case (datInState)
        DatInState_Idle: begin
        end
        
        // Wait for the start bit
        DatInState_Go: begin
            if (!datInReg[0]) begin
                $display("[SD INIT] DAT IN: started");
                datInCounter <= 128+16-1; // 128 bits payload + 16 bits CRC
                datInState <= DatInState_Go+1;
            end
        end
        
        DatInState_Go+1: begin
            // Note the function group 1 from the CMD6 status
            if (datInCounter === 8'd110) begin
                datInCMD6FnGrp1 <= datInReg;
            end
            
            if (!datInCounter) begin
                datInState <= DatInState_Go+2;
            end
        end
        
        // Check end bit
        DatInState_Go+2: begin
            if (datInReg !== 4'b1111) begin
                // TODO: expose error status
                $display("[SD INIT] DAT: end bit invalid: %b ❌", datInReg);
                `finish;
            end else begin
                $display("[SD INIT] DAT: end bit valid ✅");
            end
            
            $display("[SD INIT] DAT IN: finished");
            datInState <= DatInState_Done;
        end
        
        DatInState_Done: begin
        end
        endcase
        
        
        
        
        
        
        
        
        
        
        case (state)
        // ====================
        // CMD0 | GO_IDLE_STATE
        //   State: X -> Idle
        //   Go to idle state
        // ====================
        StateInit: begin
            $display("[SD INIT] Sending CMD0");
            cmdOutReg <= {2'b01, CMD0, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 0;
            state <= StateCmdOut;
            nextState <= StateInit+1;
        end
        
        // ====================
        // CMD8 | SEND_IF_COND
        //   State: Idle -> Idle
        //   Send interface condition
        // ====================
        StateInit+1: begin
            $display("[SD INIT] Sending CMD8");
            cmdOutReg <= {2'b01, CMD8, 32'h000001AA, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+2;
        end

        StateInit+2: begin
            // We don't need to verify the voltage in the response, since the card doesn't
            // respond if it doesn't support the voltage in CMD8 command:
            //   "If the card does not support the host supply voltage,
            //   it shall not return response and stays in Idle state."

            // Verify check pattern is what we supplied
            if (cmdInReg[15:8] !== 8'hAA) state <= StateError;
            else state <= StateInit+3;
        end

        // ====================
        // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
        //   State: Idle -> Ready
        //   Initialize
        // ====================
        StateInit+3: begin
            $display("[SD INIT] Sending ACMD41");
            cmdOutReg <= {2'b01, CMD55, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+4;
        end

        StateInit+4: begin
            // ACMD41
            //   HCS = 1 (SDHC/SDXC supported)
            //   XPC = 1 (maximum performance)
            //   S18R = 1 (switch to 1.8V signal voltage)
            //   Vdd Voltage Window = 0x8000 = 2.7-2.8V ("OCR Register Definition")
            cmdOutReg <= {2'b01, CMD41, 32'h51008000, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 0; // CRC is all 1's for ACMD41 response, so don't verify the CRC is correct
            state <= StateCmdOut;
            nextState <= StateInit+5;
        end

        StateInit+5: begin
            // Verify the command is all 1's
            if (cmdInReg[45:40] !== 6'b111111) begin
                $display("[SD INIT] Bad command: %b", cmdInReg[45:40]);
                `finish;
                state <= StateError;
            end
            // Verify CRC is all 1's
            else if (cmdInReg[7:1] !== 7'b1111111) begin
                $display("[SD INIT] Bad CRC: %b", cmdInReg[7:1]);
                `finish;
                state <= StateError;
            end
            // Retry AMCD41 if the card wasn't ready (busy)
            else if (cmdInReg[39] !== 1'b1) state <= StateInit+3;
            // Verify that we can switch to 1.8V signaling voltage (s18a)
            else if (cmdInReg[32] !== 1'b1) begin
                $display("[SD INIT] Bad s18a: %b", cmdInReg[32]);
                `finish;
                state <= StateError;
            end
            // Otherwise, proceed
            else state <= StateInit+6;
        end
        
        // ====================
        // CMD11 | VOLTAGE_SWITCH
        //   State: Ready -> Ready
        //   Switch to 1.8V signaling voltage
        // ====================
        StateInit+6: begin
            // state <= StateInit+9;
            $display("[SD INIT] Sending CMD11");
            cmdOutReg <= {2'b01, CMD11, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+7;
        end
        
        // After we get the respone, disable the clock for `ClkDisableDelay` clk12mhz cycles
        StateInit+7: begin
            $display("[SD INIT] Disabling clock for %0d cycles", ClkDisableDelay+1);
            clkEn_ <= 1;
            delayCounter <= ClkDisableDelay;
            nextState <= StateInit+8;
            state <= StateDelay;
        end
        
        // After the delay, continue once the SD card lets go of the DAT lines
        // See Section 4.2.4.2
        StateInit+8: begin
            if (clkEn_) $display("[SD INIT] Enabling clock and waiting for card ready...");
            clkEn_ <= 0;
            if (sd_datIn[0]) begin
                $display("[SD INIT] Card ready");
                state <= StateInit+9;
            end else begin
                $display("[SD INIT] Card busy");
            end
        end
        
        // ====================
        // CMD2 | ALL_SEND_CID
        //   State: Ready -> Identification
        //   Get card identification number (CID)
        // ====================
        StateInit+9: begin
            $display("[SD INIT] Sending CMD2");
            cmdOutReg <= {2'b01, CMD2, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 135;
            respCheckCRC <= 0; // CMD2 response doesn't have CRC, so don't check it
            state <= StateCmdOut;
            nextState <= StateInit+10;
        end
        
        // ====================
        // CMD3 | SEND_RELATIVE_ADDR
        //   State: Identification -> Standby
        //   Publish a new relative address (RCA)
        // ====================
        StateInit+10: begin
            $display("[SD INIT] Sending CMD3");
            cmdOutReg <= {2'b01, CMD3, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+11;
        end
        
        StateInit+11: begin
            rca <= cmdInReg[39:24];
            state <= StateInit+12;
        end
        
        // ====================
        // CMD7 | SELECT_CARD/DESELECT_CARD
        //   State: Standby -> Transfer
        //   Select card
        // ====================
        StateInit+12: begin
            $display("[SD INIT] Sending CMD7");
            cmdOutReg <= {2'b01, CMD7, {rca, 16'b0}, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+13;
        end
        
        // ====================
        // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
        //   State: Transfer -> Transfer
        //   Set bus width to 4 bits
        // ====================
        StateInit+13: begin
            $display("[SD INIT] Sending ACMD6");
            cmdOutReg <= {2'b01, CMD55, {rca, 16'b0}, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+14;
        end
        
        StateInit+14: begin
            // ACMD6
            //   Bus width = 2 (width = 4 bits)
            cmdOutReg <= {2'b01, CMD6, 32'h00000002, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+15;
        end
        
        // ====================
        // CMD6 | SWITCH_FUNC
        //   State: Transfer -> Data
        //   Switch to SDR104
        // ====================
        StateInit+15: begin
            // CMD6
            //   Mode = 1 (switch function)
            //   Group 6 (Reserved)          = 0xF (no change)
            //   Group 5 (Reserved)          = 0xF (no change)
            //   Group 4 (Current Limit)     = 0xF (no change)
            //   Group 3 (Driver Strength)   = 0xF (no change)
            //   Group 2 (Command System)    = 0xF (no change)
            //   Group 1 (Access Mode)       = 0x3 (SDR104)
            $display("[SD INIT] Sending CMD6");
            cmdOutReg <= {2'b01, CMD6, 32'h80FFFFF3, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            datInState <= DatInState_Go;
            state <= StateCmdOut;
            nextState <= StateInit+16;
        end
        
        StateInit+16: begin
            if (datInState === DatInState_Done) begin
                if (datInCMD6FnGrp1 !== 4'h3) begin
                    // TODO: signal error
                    $display("[SD INIT] CMD6 status: function group 1 invalid: %b ❌", datInCMD6FnGrp1);
                    `finish;
                end else begin
                    $display("[SD INIT] CMD6 status: function group 1 valid ✅");
                end
                state <= StateInit+17;
            end
        end
        
        // Disable the clock 8 cycles before we signal that we're done
        StateInit+17: begin
            $display("[SD INIT] Disabling clock");
            clkEn_ <= 1;
            delayCounter <= 7;
            nextState <= StateInit+18;
            state <= StateDelay;
        end
        
        StateInit+18: begin
            if (!done) $display("[SD INIT] *** INIT DONE ***");
            done <= 1;
        end
        
        
        
        
        
        
        
        
        
        StateCmdOut: begin
            cmdOutCounter <= 47;
            cmdOutActive <= 1;
            cmdOutCRCRst_ <= 1;
            state <= StateCmdOut+1;
        end
        
        StateCmdOut+1: begin
            if (cmdOutCounter === 8) begin
                cmdOutReg[47:41] <= cmdOutCRC;
            end
            
            if (!cmdOutCounter) begin
                cmdOutActive <= 0;
                cmdOutCRCRst_ <= 0;
                // The SD spec requires 8 cycles after a command or after a response,
                // before another command is issued.
                // See section 4.12, timing values N_RC and N_CC.
                delayCounter <= 7;
                state <= (cmdInCounter ? StateRespIn : StateDelay);
            end
        end
        
        
        
        
        
        
        // Wait for response to start
        StateRespIn: begin
            if (!cmdInStaged[0]) begin
                cmdInActive <= 1;
                state <= StateRespIn+1;
            end
        end
        
        // Check transmission bit
        StateRespIn+1: begin
            if (cmdInStaged[0]) begin
                $display("[SD INIT] BAD TRANSMISSION BIT");
                state <= StateError;
                
            end else begin
                cmdInCRCRst_ <= 1;
                state <= StateRespIn+2;
            end
        end
        
        // Wait for response to end
        StateRespIn+2: begin
            if (cmdInCounter === 7) respInExpectedCRC <= cmdInCRC;
            if (!cmdInCounter) begin
                cmdInActive <= 0;
                cmdInCRCRst_ <= 0;
                state <= StateRespIn+3;
            end
        end
        
        StateRespIn+3: begin
            // cmdInStaged <= ~0;
            
            $display("[SD INIT] Received response: %b [respCheckCRC: %b, our CRC: %b, their CRC: %b]", cmdInReg, respCheckCRC, respInExpectedCRC, cmdInReg[7:1]);
            
            // Verify that the CRC is OK (if requested), and that the stop bit is OK
            if ((respCheckCRC && respInExpectedCRC!==cmdInReg[7:1]) || !cmdInReg[0]) begin
                $display("[SD INIT] ***** BAD CRC *****");
                state <= StateError;
            
            end else begin
                // The SD spec requires 8 cycles after a command or after a response,
                // before another command is issued.
                // See section 4.12, timing values N_RC and N_CC.
                delayCounter <= 7;
                state <= StateDelay;
            end
        end
        
        
        
        
        // Delay state
        StateDelay: begin
            if (!delayCounter) state <= nextState;
        end
        
        
        
        
        
        
        StateError: begin
            $display("[SD INIT] ***** ERROR *****");
            `finish;
            cmdOutActive <= 0;
            cmdOutCRCRst_ <= 0;
            cmdInActive <= 0;
            cmdInCRCRst_ <= 0;
            
            // Since we don't know what state we came from, use our delay state to ensure
            // that N_RC/N_CC are met.
            // See StateDelay for more info.
            delayCounter <= 7;
            nextState <= StateInit;
            state <= StateDelay;
        end
        endcase
    end
endmodule
