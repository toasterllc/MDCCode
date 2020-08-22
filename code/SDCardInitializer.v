// Is there a minimum number of cycles after a command that we need to wait, before issuing another command?
//   Yes -- 8 cycles (N_CC)
//     -> Implemented
//
// Is there a minimum number of cycles after a response that we need to wait, before issuing another command?
//   Yes -- 8 cycles (N_RC)
//     -> Implemented
//
// For A2 cards: what procedure do we use to transition to 1.8V signaling?
//   Try doing nothing
//     -> Implemented
//
// For non-A2 cards: what procedure do we use to transition to 1.8V signaling?
//   See Section 4.2.4 (SD-Init-ACMD41.pdf)
//
// TODO: What procedure do we use to transition to a faster clock?
//
// TODO: handle never receiving a response from the card

module CRC7(
    input wire clk,
    input wire en,
    input din,
    output wire[6:0] dout,
    output wire[6:0] doutNext
);
    reg[6:0] d = 0;
    wire dx = din ^ d[6];
    wire[6:0] dnext = { d[5], d[4], d[3], d[2] ^ dx, d[1], d[0], dx };
    always @(posedge clk, negedge en)
        if (!en) d <= 0;
        else d <= dnext;
    assign dout = d;
    assign doutNext = dnext;
endmodule

module SDCardInitializer(
    input wire          clk12mhz,
    
    // SDIO port
    output wire         sd_clk,
    input wire          sd_cmdIn,
    output wire         sd_cmdOut,
    output wire         sd_cmdOutActive
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
    localparam clkDividerWidth = $clog2(DivCeil(12000000, ClkFreq));
    reg[clkDividerWidth-1:0] clkDivider = 0;
    always @(posedge clk12mhz)
        clkDivider <= clkDivider+1;
    
    wire clk = clkDivider[clkDividerWidth-1];
    
    reg[47:0] cmdOutReg = 0;
    reg[7:0] cmdOutCounter = 0;
    reg cmdOutActive = 0;
    
    reg[135:0] cmdInReg = 0;
    reg[1:0] cmdInStaged = 0;
    reg cmdInActive = 0;
    reg[7:0] cmdInCounter = 0;
    
    assign sd_clk = clk;
    assign sd_cmdOut = cmdOutReg[47];
    assign sd_cmdOutActive = cmdOutActive;
    
    // ====================
    // CRC
    // ====================
    wire[6:0] cmdOutCRC;
    reg cmdOutCRCEn = 0;
    CRC7 crc1(
        .clk(clk),
        .en(cmdOutCRCEn),
        .din(cmdOutReg[47]),
        .dout(cmdOutCRC)
    );
    
    wire[6:0] cmdInCRC;
    reg cmdInCRCEn = 0;
    CRC7 crc2(
        .clk(clk),
        .en(cmdInCRCEn),
        .din(cmdInReg[0]),
        .dout(cmdInCRC)
    );
    
    // ====================
    // State Machine
    // ====================
    localparam StateInit        = 0;     // +13
    localparam StateCmdOut      = 14;    // +1
    localparam StateRespIn      = 16;    // +3
    localparam StateDelay       = 20;    // +1
    localparam StateError       = 22;    // +0
    
    localparam CMD0 =   6'd0;      // GO_IDLE_STATE
    localparam CMD2 =   6'd2;      // ALL_SEND_CID
    localparam CMD3 =   6'd3;      // SEND_RELATIVE_ADDR
    localparam CMD6 =   6'd6;      // SWITCH_FUNC
    localparam CMD7 =   6'd7;      // SELECT_CARD/DESELECT_CARD
    localparam CMD8 =   6'd8;      // SEND_IF_COND
    localparam CMD41 =  6'd41;     // SD_SEND_OP_COND
    localparam CMD55 =  6'd55;     // APP_CMD
    
    reg[5:0] state = 0;
    reg[5:0] nextState = 0;
    reg[6:0] respInExpectedCRC = 0;
    reg respCheckCRC = 0;
    reg[15:0] sdRCA = 0;
    reg[2:0] delayCounter = 0;
    
    always @(posedge clk)
        cmdInStaged <= cmdInStaged<<1|sd_cmdIn;
    
    always @(negedge clk) begin
        if (cmdOutActive) begin
            cmdOutReg <= cmdOutReg<<1;
            cmdOutCounter <= cmdOutCounter-1;
        end
        
        if (cmdInActive) begin
            cmdInReg <= (cmdInReg<<1)|cmdInStaged[1];
            cmdInCounter <= cmdInCounter-1;
        end
        
        delayCounter <= delayCounter-1;
        
        case (state)
        // ====================
        // CMD0
        // ====================
        StateInit: begin
            $display("[SD HOST] Sending CMD0");
            cmdOutReg <= {2'b01, CMD0, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 0;
            respCheckCRC <= 0;
            state <= StateCmdOut;
            nextState <= StateInit+1;
        end
        
        // ====================
        // CMD8
        // ====================
        StateInit+1: begin
            $display("[SD HOST] Sending CMD8");
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
        // ACMD41 (CMD55, CMD41)
        // ====================
        StateInit+3: begin
            $display("[SD HOST] Sending ACMD41");
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
            //   S18R = 0 (don't switch to 1.8V signal voltage -- for A2 cards we shouldn't need to)
            //   Vdd Voltage Window = 0x8000 = 2.7-2.8V ("OCR Register Definition")
            cmdOutReg <= {2'b01, CMD41, 32'h50008000, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 0; // CRC is all 1's for ACMD41 response, so don't verify the CRC is correct
            state <= StateCmdOut;
            nextState <= StateInit+5;
        end
        
        StateInit+5: begin
            // Verify the command is all 1's
            if (cmdInReg[45:40] !== 6'b111111) state <= StateError;
            // Verify CRC is all 1's
            else if (cmdInReg[7:1] !== 7'b1111111) state <= StateError;
            // Retry AMCD41 if the card wasn't ready (busy)
            else if (cmdInReg[39] !== 1'b1) state <= StateInit+3;
            // Verify that we continuing with current signalling voltage (s18a)
            else if (cmdInReg[32] !== 1'b0) state <= StateError;
            // Otherwise, proceed
            else state <= StateInit+6;
        end
        
        // ====================
        // CMD2
        // ====================
        StateInit+6: begin
            $display("[SD HOST] Sending CMD2");
            cmdOutReg <= {2'b01, CMD2, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 135;
            respCheckCRC <= 0; // CMD2 response doesn't have CRC, so don't check it
            state <= StateCmdOut;
            nextState <= StateInit+7;
        end
        
        // ====================
        // CMD3
        // ====================
        StateInit+7: begin
            $display("[SD HOST] Sending CMD3");
            cmdOutReg <= {2'b01, CMD3, 32'h00000000, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+8;
        end
        
        StateInit+8: begin
            sdRCA <= cmdInReg[39:24];
            state <= StateInit+9;
        end
        
        // ====================
        // CMD7
        // ====================
        StateInit+9: begin
            $display("[SD HOST] Sending CMD7");
            cmdOutReg <= {2'b01, CMD7, {sdRCA, 16'b0}, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+10;
        end
        
        // ====================
        // ACMD6 (CMD55, CMD6)
        // ====================
        StateInit+10: begin
            $display("[SD HOST] Sending ACMD6");
            cmdOutReg <= {2'b01, CMD55, {sdRCA, 16'b0}, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+11;
        end
        
        StateInit+11: begin
            // ACMD6
            //   Bus width = 2 (width = 4 bits)
            cmdOutReg <= {2'b01, CMD6, 32'h00000002, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+12;
        end
        
        // ====================
        // CMD6
        // ====================
        StateInit+12: begin
            // CMD6
            //   Mode = 1 (switch function)
            //   Group 6 (Reserved)          = 0xF (no change)
            //   Group 5 (Reserved)          = 0xF (no change)
            //   Group 4 (Current Limit)     = 0xF (no change)
            //   Group 3 (Driver Strength)   = 0xF (no change)
            //   Group 2 (Command System)    = 0xF (no change)
            //   Group 1 (Access Mode)       = 0x3 (SDR104)
            $display("[SD HOST] Sending CMD6");
            cmdOutReg <= {2'b01, CMD6, 32'h80FFFFF3, 7'b0, 1'b1};
            cmdInCounter <= 47;
            respCheckCRC <= 1;
            state <= StateCmdOut;
            nextState <= StateInit+13;
        end
        
        StateInit+13: begin
            $display("[SD HOST] ***** DONE *****");
            // $finish;
        end
        
        
        
        
        
        
        
        
        
        StateCmdOut: begin
            cmdOutCounter <= 47;
            cmdOutActive <= 1;
            cmdOutCRCEn <= 1;
            state <= StateCmdOut+1;
        end
        
        StateCmdOut+1: begin
            if (cmdOutCRCEn && cmdOutCounter==8)
                cmdOutReg[47:41] <= cmdOutCRC;
                // cmdOutReg[47:41] <= 7'b1111110;
            
            if (!cmdOutCounter) begin
                cmdOutActive <= 0;
                cmdOutCRCEn <= 0;
                state <= (cmdInCounter ? StateRespIn : StateDelay);
            end
        end
        
        // Wait for response to start
        // TODO: handle never receiving a response
        StateRespIn: begin
            if (!cmdInStaged[0]) begin
                cmdInActive <= 1;
                state <= StateRespIn+1;
            end
        end
        
        // Check transmission bit
        StateRespIn+1: begin
            if (cmdInStaged[0]) begin
                $display("[SD HOST] BAD TRANSMISSION BIT");
                // $finish;
                state <= StateError;
            
            end else begin
                cmdInCRCEn <= 1;
                state <= StateRespIn+2;
            end
        end
        
        // Wait for response to end
        StateRespIn+2: begin
            if (cmdInCounter == 7) respInExpectedCRC <= cmdInCRC;
            if (!cmdInCounter) begin
                cmdInActive <= 0;
                cmdInCRCEn <= 0;
                state <= StateRespIn+3;
            end
        end
        
        StateRespIn+3: begin
            // cmdInStaged <= ~0;
            
            $display("[SD HOST] Received response: %b [respCheckCRC: %b, our CRC: %b, their CRC: %b]", cmdInReg, respCheckCRC, respInExpectedCRC, cmdInReg[7:1]);
            
            // Verify that the CRC is OK (if requested), and that the stop bit is OK
            if ((respCheckCRC && respInExpectedCRC!==cmdInReg[7:1]) || !cmdInReg[0]) begin
                $display("[SD HOST] ***** BAD CRC *****");
                // $finish;
                state <= StateError;
            
            end else
                state <= StateDelay;
        end
        
        
        
        
        // Delay state
        // The SD spec requires 8 cycles after a command or after a response,
        // before another command is issued.
        // See section 4.12, timing values N_RC and N_CC.
        StateDelay: begin
            delayCounter <= 7;
            state <= StateDelay+1;
        end
        
        StateDelay+1: begin
            if (!delayCounter) state <= nextState;
        end
        
        
        
        
        
        
        StateError: begin
            $display("[SD HOST] ***** ERROR *****");
            
            cmdOutActive <= 0;
            cmdOutCRCEn <= 0;
            cmdInActive <= 0;
            cmdInCRCEn <= 0;
            
            // Since we don't know what state we came from, use our delay state to ensure
            // that N_RC/N_CC are met.
            // See StateDelay for more info.
            nextState <= StateInit;
            state <= StateDelay;
        end
        endcase
    end
endmodule
