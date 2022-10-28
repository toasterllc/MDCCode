`ifndef SDController_v
`define SDController_v

`include "Util.v"
`include "VariableDelay.v"
`include "TogglePulse.v"
`include "CRC7.v"
`include "CRC16.v"
`include "Sync.v"
`include "Pin.v"

`define SDController_BlockLen                       512

`define SDController_Config_ClkSpeed_Off            2'b00
`define SDController_Config_ClkSpeed_Slow           2'b01
`define SDController_Config_ClkSpeed_Fast           2'b10
`define SDController_Config_ClkSpeed_Width          2
`define SDController_Config_ClkDelay_Width          4
`define SDController_Config_PinMode_PushPull        `Pin_Mode_PushPull
`define SDController_Config_PinMode_OpenDrain       `Pin_Mode_OpenDrain
`define SDController_Config_PinMode_Width           `Pin_Mode_Width

`define SDController_RespType_None                  2'b00
`define SDController_RespType_48                    2'b01
`define SDController_RespType_136                   2'b10

`define SDController_DatInType_None                 2'b00
`define SDController_DatInType_512x1                2'b01   // 512x1 bit response (eg CMD6 response)
`define SDController_DatInType_4096xN               2'b10   // 4096xN bit response (eg mass data read response)

module SDController #(
    parameter ClkFreq = 120_000_000
)(
    // Clock
    input wire          clk,
    
    // SD card port
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    
    // Config port (clock domain: async)
    input wire          config_trigger,     // Toggle signal
    input wire[`SDController_Config_ClkSpeed_Width-1:0]
                        config_clkSpeed,
    input wire[`SDController_Config_ClkDelay_Width-1:0]
                        config_clkDelay,
    input wire[`SDController_Config_PinMode_Width-1:0]
                        config_pinMode,
    
    // Command port (clock domain: `clk`)
    input wire          cmd_trigger,        // Toggle signal
    input wire[47:0]    cmd_data,
    input wire[1:0]     cmd_respType,
    input wire[1:0]     cmd_datInType,
    output reg          cmd_done = 0,       // Toggle signal
    
    // Response port (clock domain: `clk`)
    output reg          resp_done = 0,      // Toggle signal
    output reg[135:0]   resp_data = 0,
    output reg          resp_crcErr = 0,
    
    // DatOut port (clock domain: `clk`)
    input wire          datOut_trigger,     // Toggle signal
    output reg          datOut_done = 0,    // Level signal
    output reg          datOut_crcErr = 0,
    
    // DatOutRead port (clock domain: `datOutRead_clk`)
    output wire         datOutRead_clk,
    input wire          datOutRead_ready,
    output reg          datOutRead_trigger = 0,
    input wire[15:0]    datOutRead_data,
    input wire          datOutRead_done,    // Level signal
    
    // DatIn port (clock domain: `clk`)
    output reg          datIn_done = 0,     // Toggle signal
    output reg          datIn_crcErr = 0,
    
    // DatInWrite port (clock domain: `datInWrite_clk`)
    output reg          datInWrite_rst = 0,
    output wire         datInWrite_clk,
    input wire          datInWrite_ready,
    output reg          datInWrite_trigger = 0,
    output reg[15:0]    datInWrite_data = 0,
    
    // Status port (clock domain: `clk`)
    output reg          status_dat0Idle = 0
);
    // ====================
    // clk_fast (ClkFreq)
    // ====================
    localparam Clk_FastFreq = ClkFreq;
    wire clk_fast = clk;
    
    // TODO: since we're initializing with LVS, we may be able to start off in SDR12 (25 MHz).
    // TODO: try bumping clk_slow up to 25 MHz.
    // ====================
    // clk_slow (<400 kHz)
    // ====================
    localparam Clk_SlowFreq = 200000; // TODO: switch back to 400 kHz once our hardware has a physical pullup. Also, what about the comment above if we can get LVS working for all cards?
    localparam Clk_SlowDividerWidth = $clog2(`DivCeil(Clk_FastFreq, Clk_SlowFreq));
    reg[Clk_SlowDividerWidth-1:0] clk_slow_divider = 0;
    wire clk_slow = clk_slow_divider[Clk_SlowDividerWidth-1];
    always @(posedge clk_fast) begin
        clk_slow_divider <= clk_slow_divider+1;
    end
    
    // ====================
    // Config State Machine
    // ====================
    reg[1:0] cfg_state = 0;
    reg[1:0] cfg_clkSpeed = `SDController_Config_ClkSpeed_Slow;
    reg[1:0] cfg_clkSpeedNext = `SDController_Config_ClkSpeed_Slow;
    wire cfg_clkSpeed_slow = !cfg_clkSpeed[0];
    wire cfg_clkSpeed_fast = cfg_clkSpeed[1];
    reg [`SDController_Config_ClkDelay_Width-1:0] cfg_clkDelay = 0;
    reg [`SDController_Config_PinMode_Width-1:0] cfg_pinMode = 0;
    reg[1:0] cfg_delayCounter = 0;
    
    `TogglePulse(cfg_triggerPulse, config_trigger, posedge, clk_slow);
    
    always @(posedge clk_slow) begin
        if (cfg_delayCounter) begin
            cfg_delayCounter <= cfg_delayCounter-1;
        
        end else begin
            case (cfg_state)
            0: begin
            end
            
            1: begin
                // Disable clock
                cfg_clkSpeed <= `SDController_Config_ClkSpeed_Off;
                // Delay to ensure clock is stopped
                cfg_delayCounter <= 2;
                cfg_state <= 2;
            end
            
            2: begin
                cfg_clkSpeedNext <= config_clkSpeed;
                cfg_clkDelay <= config_clkDelay;
                cfg_pinMode <= config_pinMode;
                
                // Delay to let registers settle (particularly cfg_clkDelay) before re-enabling clock
                cfg_delayCounter <= 2;
                cfg_state <= 3;
            end
            
            3: begin
                // Restore clock
                cfg_clkSpeed <= cfg_clkSpeedNext;
                cfg_state <= 0;
            end
            endcase
        end
        
        if (cfg_triggerPulse) begin
            $display("[SDController:Config] Trigger");
            cfg_state <= 1;
        end
    end
    
    
    
    
    // ====================
    // clk_int
    // ====================
    `Sync(clk_slowEn, cfg_clkSpeed_slow, negedge, clk_slow);
    `Sync(clk_fastEn, cfg_clkSpeed_fast, negedge, clk_fast);
    wire clk_int = (clk_slowEn ? clk_slow : (clk_fastEn ? clk_fast : 0));
    assign datOutRead_clk = clk_int;
    assign datInWrite_clk = clk_int;
    
    // ====================
    // clk_int_delayed / cfg_clkDelay
    //   Delay `clk_int_delayed` relative to `clk_int` to correct the phase from the SD card's perspective
    //   `cfg_clkDelay` should only be set while `clk_int` is stopped
    // ====================
    wire clk_int_delayed;
    VariableDelay #(
        .Count(1<<`SDController_Config_ClkDelay_Width)
    ) VariableDelay (
        .in(clk_int),
        .sel(cfg_clkDelay),
        .out(clk_int_delayed)
    );
    
    // ====================
    // Manual SD Line Control
    // ====================
    reg         man_en_         = 0;
    reg         man_sdClk       = 0;
    wire        man_sdCmdOut    = 0;
    reg         man_sdCmdOutEn  = 0;
    wire[3:0]   man_sdDatOut    = 0;
    reg[3:0]    man_sdDatOutEn  = 0;
    `Sync(man_enSynced_, man_en_, negedge, clk_int);
    
    // ====================
    // Main State Machine
    // ====================
    reg[2:0] cmd_state = 0;
    reg cmd_crcRst = 0;
    reg cmd_crcEn = 0;
    reg cmd_crcOutEn = 0;
    reg[2:0] cmd_active = 0; // 3 bits -- see explanation where assigned
    reg[5:0] cmd_counter = 0;
    wire cmd_in;
    wire cmd_crc;
    `TogglePulse(cmd_triggerPulse, cmd_trigger, posedge, clk_int);
    
    reg[2:0] resp_state = 0;
    reg[7:0] resp_counter = 0;
    reg resp_crcRst = 0;
    reg resp_crcEn = 0;
    reg[2:0] resp_crcEnCounter = 0;
    reg resp_trigger = 0;
    reg resp_staged = 0;
    wire resp_crc;
    
    reg[135:0] cmdresp_shiftReg = 0;
    
    reg[3:0] datOut_state = 0;
    reg[2:0] datOut_active = 0; // 3 bits -- see explanation where assigned
    reg datOut_crcRst = 0;
    reg datOut_crcEn = 0;
    reg datOut_crcOutEn = 0;
    reg datOut_endBit = 0;
    reg datOut_startBit = 0;
    reg[19:0] datOut_reg = 0;
    reg[9:0] datOut_counter = 0;
    reg[1:0] datOut_readCounter = 0;
    reg[3:0] datOut_crcCounter = 0;
    wire[3:0] datOut_crc;
    wire[4:0] datOut_crcStatus = {datIn_reg[16], datIn_reg[12], datIn_reg[8], datIn_reg[4], datIn_reg[0]};
    wire datOut_crcStatusOK = datOut_crcStatus===5'b0_010_1; // 5 bits: start bit, CRC status, end bit
    reg datOut_crcStatusOKReg = 0;
    `TogglePulse(datOut_triggerPulse, datOut_trigger, posedge, clk_int);
    
    reg[2:0] datIn_state = 0;
    wire[3:0] datIn;
    reg[19:0] datIn_reg = 0;
    reg datIn_crcRst = 0;
    reg datIn_crcEn = 0;
    wire[3:0] datIn_crc;
    reg[9:0] datIn_counter = 0;
    reg[3:0] datIn_crcCounter = 0;
    reg[1:0] datInWrite_counter = 0;
    
    always @(posedge clk_int) begin
        man_en_ <= 1; // Disable manual control by default
        
        cmd_counter <= cmd_counter-1;
        // `cmd_active` is 3 bits to track whether `cmd_in` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        cmd_active <= (cmd_active<<1)|1'b0;
        cmdresp_shiftReg <= cmdresp_shiftReg<<1|resp_staged;
        if (cmd_crcOutEn) cmdresp_shiftReg[47] <= cmd_crc;
        cmd_crcRst <= 0;
        cmd_crcEn <= 0;
        cmd_crcOutEn <= 0;
        
        resp_staged <= cmd_active[2] ? 1'b1 : cmd_in;
        resp_counter <= resp_counter-1;
        resp_crcRst <= 0;
        resp_crcEn <= 0;
        if (resp_crcEnCounter) resp_crcEnCounter <= resp_crcEnCounter-1;
        
        datOut_counter <= datOut_counter-1;
        datOut_readCounter <= datOut_readCounter-1;
        datOut_crcCounter <= datOut_crcCounter-1;
        datOut_startBit <= 0; // Pulse
        datOut_endBit <= 0; // Pulse
        datOut_crcStatusOKReg <= datOut_crcStatusOK;
        datOut_reg <= datOut_reg<<4;
        if (!datOut_readCounter)    datOut_reg[15:0] <= datOutRead_data;
        if (datOut_crcOutEn)        datOut_reg[19:16] <= datOut_crc;
        if (datOut_startBit)        datOut_reg[19:16] <= 4'b0000;
        if (datOut_endBit)          datOut_reg[19:16] <= 4'b1111;
        datOut_crcRst <= 0;
        datOut_crcEn <= 0;
        datOut_crcOutEn <= 0;
        datOutRead_trigger <= 0; // Pulse
        datOut_done <= 0; // Reset by default
        
        // `datOut_active` is 3 bits to track whether `datIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        datOut_active <= (datOut_active<<1)|1'b0;
        
        datIn_reg <= (datIn_reg<<4)|(`LeftBit(datOut_active,0) ? 4'b1111 : {datIn[3], datIn[2], datIn[1], datIn[0]});
        datIn_counter <= datIn_counter-1;
        datIn_crcCounter <= datIn_crcCounter-1;
        datIn_crcRst <= 0;
        datIn_crcEn <= 0;
        datInWrite_rst <= 0; // Pulse
        datInWrite_trigger <= 0; // Pulse
        datInWrite_counter <= datInWrite_counter-1;
        datInWrite_data <= datIn_reg;
        
        status_dat0Idle <= datIn_reg[0];
        
        // ====================
        // Resp State Machine
        // ====================
        case (resp_state)
        0: begin
        end
        
        // Wait for response to start
        1: begin
            resp_crcRst <= 1;
            resp_crcErr <= 0;
            // We're accessing `cmd_respType` without synchronization, but that's
            // safe because the cmd_ domain isn't allowed to modify it until we
            // signal `resp_done`
            resp_counter <= (cmd_respType===`SDController_RespType_48 ? 48-8-2 : 136-8-2);
            // The first 8 bits are exempt from the CRC for 136-bit responses,
            // because the SD protocol is brain dead
            resp_crcEnCounter <= (cmd_respType===`SDController_RespType_136 ? 8-1 : 0);
            // Wait for response to start
            if (!resp_staged) begin
                $display("[SDController:Resp] Triggered");
                resp_state <= 2;
            end
        end
        
        2: begin
            if (!resp_crcEnCounter) begin
                resp_crcEn <= 1;
            end
            if (!resp_counter) begin
                resp_state <= 3;
            end
        end
        
        3: begin
            resp_state <= 4;
        end
        
        4: begin
            resp_counter <= 6;
            resp_state <= 5;
        end
        
        5: begin
            if (resp_crc == cmdresp_shiftReg[1]) begin
                $display("[SDController:Resp] Response: Good CRC bit (ours: %b, theirs: %b) ✅", resp_crc, cmdresp_shiftReg[1]);
            end else begin
`ifdef SIM
                $display("[SDController:Resp] Response: Bad CRC bit (ours: %b, theirs: %b) ❌", resp_crc, cmdresp_shiftReg[1]);
                `Finish;
`endif
                resp_crcErr <= 1;
            end
            
            if (!resp_counter) begin
                resp_data <= cmdresp_shiftReg;
                resp_state <= 6;
            end
        end
        
        6: begin
            if (cmdresp_shiftReg[1] === 1'b1) begin
                $display("[SDController:Resp] Response: Good end bit (%b) ✅", cmdresp_shiftReg[1]);
            end else begin
                $display("[SDController:Resp] Response: Bad end bit (%b) ❌", cmdresp_shiftReg[1]);
                `Finish;
                resp_crcErr <= 1;
            end
            
            // Signal that we're done
            resp_done <= !resp_done;
            resp_state <= 0;
        end
        endcase
        
        // ====================
        // DatOut State Machine
        // ====================
        case (datOut_state)
        0: begin
            datOut_crcErr <= 0;
        end
        
        1: begin
            datOut_counter <= 1023;
            datOut_readCounter <= 0;
            datOut_crcRst <= 1;
            datOut_startBit <= 1;
            
            if (datOutRead_ready) begin
                $display("[SDController:DatOut] Write another block");
                datOut_state <= 2;
            
            end else if (datOutRead_done) begin
                if (!datOut_done) $display("[SDController:DatOut] Done writing");
                
                // Signal that we're done while we're in this state (and therefore
                // there's no data to write), and this isn't the first block being
                // written. We inhibit datOut_done=1 before the first block so that
                // observers don't observe datOut_done=1 before writing has begun
                // -- only after writing is complete.
                datOut_done <= 1;
            end
        end
        
        2: begin
            datOut_active[0] <= 1;
            datOut_crcEn <= 1;
            
            if (!datOut_readCounter) begin
                // $display("[SDController:DatOut]   Write another word: %x", datOutRead_data);
                datOutRead_trigger <= 1;
            end
            
            if (!datOut_counter) begin
                $display("[SDController:DatOut] Done writing block");
                datOut_state <= 3;
            end
        end
        
        // Output the CRC
        3: begin
            datOut_active[0] <= 1;
            datOut_crcEn <= 1;
            datOut_crcOutEn <= 1;
            datOut_crcCounter <= 15;
            datOut_state <= 4;
        end
        
        // Wait for CRC output to finish
        4: begin
            datOut_active[0] <= 1;
            if (datOut_crcCounter) begin
                datOut_crcOutEn <= 1;
            end else begin
                datOut_endBit <= 1;
                datOut_state <= 5;
            end
        end
        
        // Output the end bit
        5: begin
            datOut_active[0] <= 1;
            datOut_state <= 6;
        end
        
        // Wait for the CRC status from the card
        6: begin
            if (!datIn_reg[16]) begin
                datOut_state <= 7;
            end
        end
        
        // Check CRC status token
        7: begin
            $display("[SDController:DatOut] DatOut: datOut_crcStatusOKReg: %b", datOut_crcStatusOKReg);
            // 5 bits: start bit, CRC status, end bit
            if (datOut_crcStatusOKReg) begin
                $display("[SDController:DatOut] DatOut: CRC status valid ✅");
            end else begin
                $display("[SDController:DatOut] DatOut: CRC status invalid: %b ❌", datOut_crcStatusOKReg);
                `Finish;
                datOut_crcErr <= 1;
            end
            datOut_state <= 8;
        end
        
        // Wait until the card stops being busy (busy == DAT0 low)
        8: begin
            if (datIn_reg[0]) begin
                $display("[SDController:DatOut] Card ready (%b)", datIn_reg[0]);
                datOut_state <= 1;
            
            end else begin
                $display("[SDController:DatOut] Card busy (%b)", datIn_reg[0]);
            end
            
`ifdef SIM
            if (!`ValidBits(datIn_reg)) begin
                $display("[SDController:DatOut] Invalid datIn_reg bits: %b ❌", datIn_reg);
                `Finish;
            end
`endif
        end
        endcase
        
        if (datOut_triggerPulse) begin
            $display("[SDController:DatOut] Triggered");
            datOut_state <= 1;
        end
        
        // ====================
        // DatIn State Machine
        // ====================
        case (datIn_state)
        0: begin
        end
        
        1: begin
            datIn_crcErr <= 0;
            datInWrite_rst <= 1;
            datIn_state <= 2;
        end
        
        2: begin
            datIn_crcRst <= 1;
            datIn_state <= 3;
        end
        
        3: begin
            // We're accessing `cmd_datInType` without synchronization, but that's
            // safe because the cmd_ domain isn't allowed to modify it until we
            // signal `datIn_done`
            // TODO: perf: try registering the value for datIn_counter
            datIn_counter <= (cmd_datInType===`SDController_DatInType_512x1 ? 127 : 1023);
            datInWrite_counter <= 3;
            if (!datIn_reg[0]) begin
                $display("[SDController:DatIn] Triggered");
                datIn_state <= 4;
            end
        end
        
        4: begin
            datIn_crcEn <= 1;
            
            if (!datInWrite_counter) begin
                // $display("[SDController:DatIn] Received word: %h", datIn_reg[15:0]);
                datInWrite_trigger <= 1;
            end
            
            // Stay in this state until datIn_counter==0
            if (!datIn_counter) begin
                datIn_crcCounter <= 15;
                datIn_state <= 5;
            end
        end
        
        5: begin
            if (datIn_crc[3] == datIn_reg[3]) begin
                $display("[SDController:DatIn] DAT3 CRC valid ✅ (ours: %b, theirs: %b)", datIn_crc[3], datIn_reg[3]);
            end else begin
                $display("[SDController:DatIn] Bad DAT3 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[3], datIn_reg[3]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (datIn_crc[2] == datIn_reg[2]) begin
                $display("[SDController:DatIn] DAT2 CRC valid ✅ (ours: %b, theirs: %b)", datIn_crc[2], datIn_reg[2]);
            end else begin
                $display("[SDController:DatIn] Bad DAT2 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[2], datIn_reg[2]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (datIn_crc[1] == datIn_reg[1]) begin
                $display("[SDController:DatIn] DAT1 CRC valid ✅ (ours: %b, theirs: %b)", datIn_crc[1], datIn_reg[1]);
            end else begin
                $display("[SDController:DatIn] Bad DAT1 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[1], datIn_reg[1]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (datIn_crc[0] == datIn_reg[0]) begin
                $display("[SDController:DatIn] DAT0 CRC valid ✅ (ours: %b, theirs: %b)", datIn_crc[0], datIn_reg[0]);
            end else begin
                $display("[SDController:DatIn] Bad DAT0 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[0], datIn_reg[0]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (!datIn_crcCounter) begin
                datIn_state <= 6;
            end
        end
        
        6: begin
            // Check end bits
            if (datIn_reg[3:0] === 4'b1111) begin
                $display("[SDController:DatIn] Good end bits ✅ (expected: %b, got: 4'b1111) ✅", datIn_reg[3:0]);
            end else begin
                $display("[SDController:DatIn] Bad end bits ❌ (expected: %b, got: 4'b1111) ✅", datIn_reg[3:0]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            datIn_done <= !datIn_done; // Signal that the DatIn is complete
            
            if (cmd_datInType===`SDController_DatInType_4096xN) begin
                datIn_state <= 7;
            end else begin
                datIn_state <= 0;
            end
        end
        
        7: begin
            // Disable sd_clk while we're in this state
            man_en_ <= 0;
            man_sdClk <= 0;
            
            // Wait until the FIFO can accept data
            if (datInWrite_ready) begin
                datIn_state <= 2;
            end
        end
        endcase
        
        // ====================
        // CmdOut State Machine
        //   This needs to be below the Resp/DatOut/DatIn state machines, so that the Cmd
        //   assignments take precedence (such as when assigning resp_state/datIn_state.)
        // ====================
        case (cmd_state)
        0: begin
            cmd_counter <= 1;
        end
        
        1: begin
            $display("[SDController:Cmd] Triggered");
            // Reset state machines
            resp_state <= 0;
            datOut_state <= 0;
            datIn_state <= 0;
            cmd_crcRst <= 1;
            // Delay a few cycles (while manual control is potentially being disabled) before issuing the SD command.
            // This is necessary because the DatIn state machine halts the clock (using `man_en_`) until
            // the FIFO has space (`datInWrite_ready`). So if we're coming from that state, we need to
            // wait until the clock is unhalted, which will happen automatically because we reset
            // resp_state/datOut_state/datIn_state.
            if (!cmd_counter) begin
                cmd_state <= 2;
            end
        end
        
        2: begin
            cmd_counter <= 37;
            cmd_active[0] <= 1;
            cmd_crcEn <= 1;
            cmdresp_shiftReg <= cmd_data;
            cmd_state <= 3;
        end
        
        3: begin
            cmd_active[0] <= 1;
            cmd_crcEn <= 1;
            if (!cmd_counter) cmd_state <= 4;
        end
        
        // Start CRC output
        4: begin
            cmd_active[0] <= 1;
            cmd_crcEn <= 1;
            cmd_crcOutEn <= 1;
            cmd_counter <= 6;
            cmd_state <= 5;
        end
        
        // Wait until CRC output is finished
        5: begin
            cmd_active[0] <= 1;
            if (cmd_counter) cmd_crcOutEn <= 1;
            else cmd_state <= 6;
        end
        
        6: begin
            cmd_active[0] <= 1;
            $display("[SDController:Cmd] Done");
            cmd_done <= !cmd_done;
            resp_state <= (cmd_respType===`SDController_RespType_None ? 0 : 1);
            datIn_state <= (cmd_datInType===`SDController_DatInType_None ? 0 : 1);
            cmd_state <= 0;
        end
        endcase
        
        if (cmd_triggerPulse) begin
            cmd_state <= 1;
        end
    end
    
    // ====================
    // Pin: sd_clk
    // ====================
    wire sd_clkOut = (!man_enSynced_ ? man_sdClk : clk_int_delayed);
    PinOut #(
        .Reg(0),
        .Pullup(1) // Remove once we have a physical hardware pullup
    ) PinOut_sd_clk (
        .clk(),
        // .mode(`SDController_Config_PinMode_PushPull),     // TODO: remove and uncomment below once we have a physical pullup
        .mode(cfg_pinMode),
        .out(sd_clkOut),
        .pin(sd_clk)
    );
    
    // ====================
    // Pin: sd_cmd
    // ====================
    wire sd_cmdDir = (!man_enSynced_ ? man_sdCmdOutEn : cmd_active[0]);
    wire sd_cmdOut = (!man_enSynced_ ? man_sdCmdOut : cmdresp_shiftReg[47]);
    PinInOut #(
        .Reg(1)
    ) PinInOut_sd_cmd (
        .clk(clk_int),
        .mode(cfg_pinMode),
        .dir(sd_cmdDir),
        .out(sd_cmdOut),
        .in(cmd_in),
        .pin(sd_cmd)
    );
    
    // ====================
    // Pin: sd_dat[3:0]
    // ====================
    genvar i;
    for (i=0; i<4; i=i+1) begin
        SB_IO #(
            .PIN_TYPE(6'b1101_00)
        ) SB_IO_sd_dat (
            .INPUT_CLK      (clk_int                                                    ),
            .OUTPUT_CLK     (clk_int                                                    ),
            .PACKAGE_PIN    (sd_dat[i]                                                  ),
            .OUTPUT_ENABLE  (!man_enSynced_ ? man_sdDatOutEn[i]    : datOut_active[0]   ),
            .D_OUT_0        (!man_enSynced_ ? man_sdDatOut[i]      : datOut_reg[16+i]   ),
            .D_IN_0         (datIn[i]                                                   )
        );
    end
    
    // ====================
    // CRC: cmd_crc
    // ====================
    CRC7 #(
        .Delay(-1)
    ) CRC7_cmd_crc(
        .clk(clk_int),
        .rst(cmd_crcRst),
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
        .rst(resp_crcRst),
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
            .rst(datOut_crcRst),
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
            .Delay(-1)
        ) CRC16_dat(
            .clk(clk_int),
            .rst(datIn_crcRst),
            .en(datIn_crcEn),
            .din(datIn_reg[4+i]),
            .dout(datIn_crc[i])
        );
    end
endmodule

`endif
