`ifndef SDController_v
`define SDController_v

`include "Util.v"
`include "VariableDelay.v"
`include "BankFIFO.v"
`include "CRC7.v"
`include "CRC16.v"

module SDController #(
    parameter ClkFreq           = 120_000_000,
    localparam ClkDelayWidth    = 4
)(
    // Clock
    input wire clk,
    
    // SD card
    output wire     sdcard_clk,
    inout wire      sdcard_cmd,
    inout wire[3:0] sdcard_dat,
    
    // Control
    input wire                      ctrl_clkSlowEn,
    input wire                      ctrl_clkFastEn,
    input wire[ClkDelayWidth-1:0]   ctrl_clkDelay,
    input wire[47:0]                ctrl_cmd,
    input wire                      ctrl_cmdRespType_48,
    input wire                      ctrl_cmdRespType_136,
    input wire                      ctrl_cmdDatInType_512,
    input wire                      ctrl_cmdTrigger, // Toggle
    input wire                      ctrl_abort, // Toggle
    
    // DatOut
    input wire          datOut_writeClk,
    input wire          datOut_writeTrigger,
    input wire[15:0]    datOut_writeData,
    output wire         datOut_writeOK,
    
    // Status
    output reg          status_cmdDone = 0, // Toggle
    output reg          status_respDone = 0, // Toggle
    output reg          status_respCRCErr = 0,
    output reg[47:0]    status_resp = 0,
    output reg          status_datOutDone = 0, // Toggle
    output reg          status_datOutCRCErr = 0,
    output reg          status_datInDone = 0, // Toggle
    output reg          status_datInCRCErr = 0,
    output reg[3:0]     status_datInCMD6AccessMode = 0,
    output reg          status_dat0Idle = 0
);
    // ====================
    // clk_fast (ClkFreq)
    // ====================
    localparam Clk_Fast_Freq = ClkFreq;
    wire clk_fast = clk;
    
    // ====================
    // clk_slow (400 kHz)
    // ====================
    localparam Clk_Slow_Freq = 400000;
    localparam Clk_Slow_DividerWidth = $clog2(DivCeil(Clk_Fast_Freq, Clk_Slow_Freq));
    reg[Clk_Slow_DividerWidth-1:0] clk_slow_divider = 0;
    wire clk_slow = clk_slow_divider[Clk_Slow_DividerWidth-1];
    always @(posedge clk_fast) begin
        clk_slow_divider <= clk_slow_divider+1;
    end
    
    // ====================
    // clk_int
    // ====================
    `Sync(clk_slow_en, ctrl_clkSlowEn, negedge, clk_slow);
    `Sync(clk_fast_en, ctrl_clkFastEn, negedge, clk_fast);
    wire clk_int = (clk_slow_en ? clk_slow : (clk_fast_en ? clk_fast : 0));
    
    // ====================
    // sdcard_clk / ctrl_clkDelay
    //   Delay `sdcard_clk` relative to `clk_int` to correct the phase from the SD card's perspective
    //   `ctrl_clkDelay` should only be set while `clk_int` is stopped
    // ====================
    VariableDelay #(
        .Count(1<<ClkDelayWidth)
    ) VariableDelay (
        .in(clk_int),
        .sel(ctrl_clkDelay),
        .out(sdcard_clk)
    );
    
    `TogglePulse(cmd_trigger, ctrl_cmdTrigger, posedge, clk_int);
    `ToggleAck(abort, abort_ack, ctrl_abort, posedge, clk_int);
    
    
    
    
    
    // ====================
    // Dat Out FIFO
    // ====================
    reg datOut_readTrigger = 0;
    wire[15:0] datOut_readData;
    wire datOut_readOK;
    wire datOut_readBank;
    BankFIFO #(
        .W(16),
        .N(8)
    ) BankFIFO(
        .w_clk(datOut_writeClk),
        .w_trigger(datOut_writeTrigger),
        .w_data(datOut_writeData),
        .w_ok(datOut_writeOK),
        
        .r_clk(clk_int),
        .r_trigger(datOut_readTrigger),
        .r_data(datOut_readData),
        .r_ok(datOut_readOK),
        .r_bank(datOut_readBank)
    );
    
    
    
    
    
    
    
    
    // ====================
    // State Machine
    // ====================
    reg[11:0] cmd_state = 0;
    reg cmd_stateInit = 0;
    reg cmd_crcEn = 0;
    reg cmd_crcOutEn = 0;
    reg[2:0] cmd_active = 0; // 3 bits -- see explanation where assigned
    reg[5:0] cmd_counter = 0;
    wire cmd_in;
    wire cmd_crc;
    
    reg[9:0] resp_state = 0;
    reg resp_stateInit = 0;
    reg[7:0] resp_counter = 0;
    reg resp_crcEn = 0;
    reg resp_trigger = 0;
    reg resp_staged = 0;
    wire resp_crc;
    
    reg[47:0] cmdresp_shiftReg = 0;
    
    reg[3:0] datOut_state = 0;
    reg[2:0] datOut_active = 0; // 3 bits -- see explanation where assigned
    reg datOut_crcEn = 0;
    reg datOut_crcOutEn = 0;
    reg datOut_endBit = 0;
    reg datOut_ending = 0;
    reg datOut_prevBank = 0;
    reg datOut_startBit = 0;
    reg[19:0] datOut_reg = 0;
    reg[1:0] datOut_counter = 0;
    reg[3:0] datOut_crcCounter = 0;
    wire[3:0] datOut_crc;
    wire[4:0] datOut_crcStatus = {datIn_reg[16], datIn_reg[12], datIn_reg[8], datIn_reg[4], datIn_reg[0]};
    wire datOut_crcStatusOK = datOut_crcStatus===5'b0_010_1; // 5 bits: start bit, CRC status, end bit
    reg datOut_crcStatusOKReg = 0;
    
    reg[4:0] datIn_state = 0;
    reg datIn_stateInit = 0;
    reg datIn_trigger = 0;
    wire[3:0] datIn;
    reg[19:0] datIn_reg = 0;
    reg datIn_crcEn = 0;
    wire[3:0] datIn_crc;
    reg[6:0] datIn_counter = 0;
    reg[3:0] datIn_crcCounter = 0;
    
    always @(posedge clk_int) begin
        cmd_state <= cmd_state<<1|!cmd_stateInit|cmd_state[$size(cmd_state)-1];
        cmd_stateInit <= 1;
        cmd_counter <= cmd_counter-1;
        // `cmd_active` is 3 bits to track whether `cmd_in` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        cmd_active <= (cmd_active<<1)|cmd_active[0];
        
        cmdresp_shiftReg <= cmdresp_shiftReg<<1|resp_staged;
        if (cmd_crcOutEn)  cmdresp_shiftReg[47] <= cmd_crc;
        
        resp_state <= resp_state<<1|!resp_stateInit|resp_state[$size(resp_state)-1];
        resp_stateInit <= 1;
        resp_staged <= cmd_active[2] ? 1'b1 : cmd_in;
        resp_counter <= resp_counter-1;
        
        datOut_counter <= datOut_counter-1;
        datOut_crcCounter <= datOut_crcCounter-1;
        datOut_readTrigger <= 0; // Pulse
        datOut_prevBank <= datOut_readBank;
        datOut_ending <= datOut_ending|(datOut_prevBank && !datOut_readBank);
        datOut_startBit <= 0; // Pulse
        datOut_endBit <= 0; // Pulse
        datOut_crcStatusOKReg <= datOut_crcStatusOK;
        datOut_reg <= datOut_reg<<4;
        if (!datOut_counter)  datOut_reg[15:0] <= datOut_readData;
        if (datOut_crcOutEn)  datOut_reg[19:16] <= datOut_crc;
        if (datOut_startBit)  datOut_reg[19:16] <= 4'b0000;
        if (datOut_endBit)    datOut_reg[19:16] <= 4'b1111;
        
        // `datOut_active` is 3 bits to track whether `datIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        datOut_active <= (datOut_active<<1)|datOut_active[0];
        
        datIn_state <= datIn_state<<1|!datIn_stateInit|datIn_state[$size(datIn_state)-1];
        datIn_stateInit <= 1;
        datIn_reg <= (datIn_reg<<4)|(datOut_active[2] ? 4'b1111 : {datIn[3], datIn[2], datIn[1], datIn[0]});
        datIn_counter <= datIn_counter-1;
        datIn_crcCounter <= datIn_crcCounter-1;
        status_dat0Idle <= datIn_reg[0];
        
        // ====================
        // CmdOut State Machine
        // ====================
        if (cmd_state[0]) begin
            cmd_active[0] <= 0;
            cmd_counter <= 38;
            if (cmd_trigger) begin
                $display("[SD-CTRL:CMDOUT] Command to be clocked out: %b", ctrl_cmd);
                // Clear outstanding abort when starting a new command
                if (abort) abort_ack <= !abort_ack;
            end else begin
                // Stay in this state
                cmd_state[1:0] <= cmd_state[1:0];
            end
        end
        
        if (cmd_state[1]) begin
            cmd_active[0] <= 1;
            cmdresp_shiftReg <= ctrl_cmd;
            cmd_crcEn <= 1;
        end
        
        if (cmd_state[2]) begin
            if (cmd_counter) begin
                // Stay in this state
                cmd_state[3:2] <= cmd_state[3:2];
            end
        end
        
        if (cmd_state[3]) begin
            cmd_crcOutEn <= 1;
        end
        
        if (cmd_state[4]) begin
            cmd_crcEn <= 0;
        end
        
        if (cmd_state[10]) begin
            cmd_crcOutEn <= 0;
            status_cmdDone <= !status_cmdDone;
            resp_trigger <= (ctrl_cmdRespType_48 || ctrl_cmdRespType_136);
            datIn_trigger <= ctrl_cmdDatInType_512;
        end
        
        
        
        
        // ====================
        // Resp State Machine
        // ====================
        if (resp_state[0]) begin
            resp_crcEn <= 0;
            // We're accessing `ctrl_sdRespType` without synchronization, but that's
            // safe because the ctrl_ domain isn't allowed to modify it until we
            // signal `status_respDone`
            resp_counter <= (ctrl_cmdRespType_48 ? 48 : 136) - 8;
            
            // Handle being aborted
            if (abort) begin
                resp_trigger <= 0;
                // Signal that we're done
                // Only do this if `resp_trigger`=1 though, otherwise toggling `status_respDone`
                // will toggle us from Done->!Done, instead of remaining Done.
                if (resp_trigger) status_respDone <= !status_respDone;
                
                // Stay in this state
                resp_state[1:0] <= resp_state[1:0];
            
            end else if (resp_trigger && !resp_staged) begin
                $display("[SD-CTRL:RESP] Triggered");
                resp_trigger <= 0;
                status_respCRCErr <= 0;
                resp_crcEn <= 1;
            
            end else begin
                // Stay in this state
                resp_state[1:0] <= resp_state[1:0];
            end
        end
        
        if (resp_state[1]) begin
            if (!resp_counter) begin
                resp_crcEn <= 0;
            end else begin
                resp_state[2:1] <= resp_state[2:1];
            end
        end
        
        if (resp_state[8:2]) begin
            if (resp_crc === cmdresp_shiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good CRC bit (ours: %b, theirs: %b) ✅", resp_crc, cmdresp_shiftReg[1]);
            end else begin
                $display("[SD-CTRL:RESP] Response: Bad CRC bit (ours: %b, theirs: %b) ❌", resp_crc, cmdresp_shiftReg[1]);
                status_respCRCErr <= 1;
            end
        end
        
        if (resp_state[9]) begin
            if (cmdresp_shiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good end bit ✅");
            end else begin
                $display("[SD-CTRL:RESP] Response: Bad end bit ❌");
                status_respCRCErr <= 1;
            end
            
            // Ideally we'd assign `status_resp` on the previous clock cycle
            // so that we didn't need this right-shift, but that hurts
            // our perf quite a bit. So since the high bit of SD card
            // commands/responses is always zero, assign it here.
            status_resp <= cmdresp_shiftReg>>1;
            // Signal that the response was received
            status_respDone <= !status_respDone;
        end
        
        
        
        
        // ====================
        // DatOut State Machine
        // ====================
        case (datOut_state)
        0: begin
            if (datOut_readOK) begin
                $display("[SD-CTRL:DATOUT] Write session starting");
                status_datOutCRCErr <= 0;
                datOut_state <= 1;
            end
        end
        
        1: begin
            $display("[SD-CTRL:DATOUT] Write another block");
            datOut_counter <= 0;
            datOut_crcCounter <= 0;
            datOut_active[0] <= 0;
            datOut_ending <= 0;
            datOut_crcEn <= 0;
            datOut_startBit <= 1;
            datOut_state <= 2;
        end
        
        2: begin
            datOut_active[0] <= 1;
            datOut_crcEn <= 1;
            
            if (!datOut_counter) begin
                // $display("[SD-CTRL:DATOUT]   Write another word: %x", datOut_readData);
                datOut_readTrigger <= 1;
            end
            
            if (datOut_ending) begin
                $display("[SD-CTRL:DATOUT] Done writing");
                datOut_state <= 3;
            end
        end
        
        // Wait for CRC to be clocked out and supply end bit
        3: begin
            datOut_crcOutEn <= 1;
            datOut_state <= 4;
        end
        
        4: begin
            if (!datOut_crcCounter) begin
                datOut_crcEn <= 0;
                datOut_endBit <= 1;
                datOut_state <= 5;
            end
        end
        
        // Disable DatOut when we finish outputting the CRC,
        // and wait for the CRC status from the card.
        5: begin
            datOut_crcOutEn <= 0;
            if (datOut_crcCounter === 14) begin
                datOut_active[0] <= 0;
            end
            
            // SD response timeout point:
            //   check if we've been aborted before checking SD response
            if (abort) begin
                datOut_state <= 8;
            
            end else if (!datIn_reg[16]) begin
                datOut_state <= 6;
            end
        end
        
        // Check CRC status token
        6: begin
            $display("[SD-CTRL:DATOUT] DatOut: datOut_crcStatusOKReg: %b", datOut_crcStatusOKReg);
            // 5 bits: start bit, CRC status, end bit
            if (datOut_crcStatusOKReg) begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status valid ✅");
            end else begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status invalid: %b ❌", datOut_crcStatusOKReg);
                status_datOutCRCErr <= 1;
            end
            datOut_state <= 7;
        end
        
        // Wait until the card stops being busy (busy == DAT0 low)
        7: begin
            // SD response timeout point:
            //   check if we've been aborted before checking SD response
            if (abort) begin
                datOut_state <= 8;
            
            end else if (datIn_reg[0]) begin
                $display("[SD-CTRL:DATOUT] Card ready");
                
                if (datOut_readOK) begin
                    datOut_state <= 1;
                
                end else begin
                    // Signal that DatOut is done
                    status_datOutDone <= !status_datOutDone;
                    datOut_state <= 0;
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
            datOut_active[0] <= 0;
            
            // Drain only on !datOut_counter (the same as DatOut does normally)
            // so that we don't read too fast. If we read faster than we write,
            // then `!datOut_readOK`=1, and we'll signal that we're done and
            // transition to state 0 before we're actually done.
            if (!datOut_counter) begin
                datOut_readTrigger <= 1;
            end
            
            if (!datOut_readOK) begin
                // Signal that DatOut is done
                status_datOutDone <= !status_datOutDone;
                datOut_state <= 0;
            end
        end
        endcase
        
        
        
        
        
        // ====================
        // DatIn State Machine
        // ====================
        if (datIn_state[0]) begin
            datIn_counter <= 127;
            datIn_crcEn <= 0;
            
            if (abort) begin
                datIn_trigger <= 0;
                
                // Signal that we're done
                // Only do this if `datIn_trigger`=1 though, otherwise toggling `status_datInDone`
                // will toggle us from Done->!Done, instead of remaining Done.
                if (datIn_trigger) status_datInDone <= !status_datInDone;
                
                // Stay in this state
                datIn_state[1:0] <= datIn_state[1:0];
            
            end else if (datIn_trigger && !datIn_reg[0]) begin
                $display("[SD-CTRL:DATIN] Triggered");
                datIn_trigger <= 0;
                status_datInCRCErr <= 0;
                datIn_crcEn <= 1;
            
            end else begin
                // Stay in this state
                datIn_state[1:0] <= datIn_state[1:0];
            end
        end
        
        if (datIn_state[1]) begin
            // Stash the access mode from the DatIn response.
            // (This assumes we're receiving a CMD6 response.)
            if (datIn_counter === 7'd94) begin
                status_datInCMD6AccessMode <= datIn_reg[3:0];
            end
            
            if (!datIn_counter) begin
                datIn_crcEn <= 0;
            end
            
            // Stay in this state until datIn_counter==0
            if (datIn_counter) begin
                datIn_state[2:1] <= datIn_state[2:1];
            end
        end
        
        if (datIn_state[2]) begin
            datIn_crcCounter <= 15;
        end
        
        if (datIn_state[3]) begin
            if (datIn_crc[3] === datIn_reg[7]) begin
                $display("[SD-CTRL:DATIN] DAT3 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT3 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[3], datIn_reg[7]);
                status_datInCRCErr <= 1;
            end
            
            if (datIn_crc[2] === datIn_reg[6]) begin
                $display("[SD-CTRL:DATIN] DAT2 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT2 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[2], datIn_reg[6]);
                status_datInCRCErr <= 1;
            end
            
            if (datIn_crc[1] === datIn_reg[5]) begin
                $display("[SD-CTRL:DATIN] DAT1 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT1 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[1], datIn_reg[5]);
                status_datInCRCErr <= 1;
            end
            
            if (datIn_crc[0] === datIn_reg[4]) begin
                $display("[SD-CTRL:DATIN] DAT0 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT0 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[0], datIn_reg[4]);
                status_datInCRCErr <= 1;
            end
            
            if (datIn_crcCounter) begin
                // Stay in this state
                datIn_state[4:3] <= datIn_state[4:3];
            end
        end
        
        if (datIn_state[4]) begin
            if (datIn_reg[7:4] === 4'b1111) begin
                $display("[SD-CTRL:DATIN] Good end bit ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad end bit ❌");
                status_datInCRCErr <= 1;
            end
            // Signal that the DatIn is complete
            status_datInDone <= !status_datInDone;
        end
    end
    
    // ====================
    // Pin: sdcard_cmd
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_sdcard_cmd (
        .INPUT_CLK(clk_int),
        .OUTPUT_CLK(clk_int),
        .PACKAGE_PIN(sdcard_cmd),
        .OUTPUT_ENABLE(cmd_active[0]),
        .D_OUT_0(cmdresp_shiftReg[47]),
        .D_IN_0(cmd_in)
    );
    
    // ====================
    // Pin: sdcard_dat[3:0]
    // ====================
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_00)
        ) SB_IO_sdcard_dat (
            .INPUT_CLK(clk_int),
            .OUTPUT_CLK(clk_int),
            .PACKAGE_PIN(sdcard_dat[i]),
            .OUTPUT_ENABLE(datOut_active[0]),
            .D_OUT_0(datOut_reg[16+i]),
            .D_IN_0(datIn[i])
        );
    end
    
    // ====================
    // CRC: cmd_crc
    // ====================
    CRC7 #(
        .Delay(-1)
    ) CRC7_cmd_crc(
        .clk(clk_int),
        .en(cmd_crcEn),
        .din(cmdresp_shiftReg[47]),
        .dout(cmd_crc)
    );
    
    // ====================
    // CRC: resp_crc
    // ====================
    CRC7 #(
        .Delay(1)
    ) CRC7_resp_crc(
        .clk(clk_int),
        .en(resp_crcEn),
        .din(cmdresp_shiftReg[0]),
        .dout(resp_crc)
    );
    
    // ====================
    // CRC: datOut_crc
    // ====================
    for (i=0; i<4; i=i+1) begin
        CRC16 #(
            .Delay(-1)
        ) CRC16_datOut_crc(
            .clk(clk_int),
            .en(datOut_crcEn),
            .din(datOut_reg[16+i]),
            .dout(datOut_crc[i])
        );
    end
    
    // ====================
    // CRC: datIn_crc
    // ====================
    for (i=0; i<4; i=i+1) begin
        CRC16 #(
            .Delay(1)
        ) CRC16_dat(
            .clk(clk_int),
            .en(datIn_crcEn),
            .din(datIn_reg[i]),
            .dout(datIn_crc[i])
        );
    end
endmodule

`endif
