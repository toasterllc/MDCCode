`ifndef SDController_v
`define SDController_v

`include "Util.v"
`include "VariableDelay.v"
`include "BankFIFO.v"
`include "CRC7.v"
`include "CRC16.v"

`define SDController_ClkSrc_Speed_Off       2'b00
`define SDController_ClkSrc_Speed_Slow      2'b01
`define SDController_ClkSrc_Speed_Fast      2'b10
`define SDController_ClkSrc_Delay_Width     4

`define SDController_RespType_None          2'b00
`define SDController_RespType_48            2'b01
`define SDController_RespType_136           2'b10

`define SDController_DatInType_None         1'b0
`define SDController_DatInType_512          1'b1

module SDController #(
    parameter ClkFreq = 120_000_000
)(
    // Clock
    input wire clk,
    
    // SD card port
    output wire     sdcard_clk,
    inout wire      sdcard_cmd,
    inout wire[3:0] sdcard_dat,
    
    // Clock source port (clock domain: async)
    input wire[1:0]                                     clksrc_speed,
    input wire[`SDController_ClkSrc_Delay_Width-1:0]    clksrc_delay,
    
    // Command port (clock domain: `clk`)
    input wire          cmd_trigger, // Toggle
    input wire[47:0]    cmd_data,
    input wire[1:0]     cmd_respType,
    input wire          cmd_datInType,
    output reg          cmd_done = 0, // Toggle
    
    // Response port (clock domain: `clk`)
    output reg          resp_done = 0, // Toggle
    output reg[47:0]    resp_data = 0,
    output reg          resp_crcErr = 0,
    
    // DatOut port (clock domain: `clk`)
    input wire datOut_start,        // Toggle
    output reg datOut_ready = 0,    // Toggle
    output reg datOut_done = 0,     // Toggle
    output reg datOut_crcErr = 0,
    
    // DatOutWrite port (clock domain: `datOutWrite_clk`)
    input wire          datOutWrite_clk,
    output wire         datOutWrite_ready,
    input wire          datOutWrite_trigger,
    input wire[15:0]    datOutWrite_data,
    
    // DatIn port (clock domain: `clk`)
    output reg      datIn_done = 0, // Toggle
    output reg      datIn_crcErr = 0,
    output reg[3:0] datIn_cmd6AccessMode = 0,
    
    // Status port (clock domain: `clk`)
    output reg status_dat0Idle = 0
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
    wire clksrc_slow = clksrc_speed[0];
    wire clksrc_fast = clksrc_speed[1];
    `Sync(clk_slow_en, clksrc_slow, negedge, clk_slow);
    `Sync(clk_fast_en, clksrc_fast, negedge, clk_fast);
    wire clk_int = (clk_slow_en ? clk_slow : (clk_fast_en ? clk_fast : 0));
    
    // ====================
    // sdcard_clk / clksrc_delay
    //   Delay `sdcard_clk` relative to `clk_int` to correct the phase from the SD card's perspective
    //   `clksrc_delay` should only be set while `clk_int` is stopped
    // ====================
    VariableDelay #(
        .Count(1<<`SDController_ClkSrc_Delay_Width)
    ) VariableDelay (
        .in(clk_int),
        .sel(clksrc_delay),
        .out(sdcard_clk)
    );
    
    
    
    
    
    
    
    
    // ====================
    // State Machine
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
    reg resp_trigger = 0;
    reg resp_staged = 0;
    wire resp_crc;
    
    reg[47:0] cmdresp_shiftReg = 0;
    
    reg[3:0] datOut_state = 0;
    reg[2:0] datOut_active = 0; // 3 bits -- see explanation where assigned
    reg datOut_crcRst = 0;
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
    
    reg datOutFIFO_rst = 0;
    wire datOutFIFO_rstDone;
    wire datOutFIFO_writeReady;
    reg datOutFIFO_readTrigger = 0;
    wire[15:0] datOutFIFO_readData;
    wire datOutFIFO_readReady;
    wire datOutFIFO_readBank;
    `TogglePulse(datOut_startPulse, datOut_start, posedge, clk_int);
    `TogglePulse(datOut_fifoRstDone, datOutFIFO_rstDone, posedge, clk_int);
    
    reg[2:0] datIn_state = 0;
    wire[3:0] datIn;
    reg[19:0] datIn_reg = 0;
    reg datIn_crcRst = 0;
    reg datIn_crcEn = 0;
    wire[3:0] datIn_crc;
    reg[6:0] datIn_counter = 0;
    reg[3:0] datIn_crcCounter = 0;
    
    always @(posedge clk_int) begin
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
        
        datOut_counter <= datOut_counter-1;
        datOut_crcCounter <= datOut_crcCounter-1;
        datOutFIFO_readTrigger <= 0; // Pulse
        datOut_prevBank <= datOutFIFO_readBank;
        datOut_ending <= datOut_ending|(datOut_prevBank && !datOutFIFO_readBank);
        datOut_startBit <= 0; // Pulse
        datOut_endBit <= 0; // Pulse
        datOut_crcStatusOKReg <= datOut_crcStatusOK;
        datOut_reg <= datOut_reg<<4;
        if (!datOut_counter)  datOut_reg[15:0] <= datOutFIFO_readData;
        if (datOut_crcOutEn)  datOut_reg[19:16] <= datOut_crc;
        if (datOut_startBit)  datOut_reg[19:16] <= 4'b0000;
        if (datOut_endBit)    datOut_reg[19:16] <= 4'b1111;
        datOut_crcRst <= 0;
        datOut_crcEn <= 0;
        datOut_crcOutEn <= 0;
        
        // `datOut_active` is 3 bits to track whether `datIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        datOut_active <= (datOut_active<<1)|1'b0;
        
        datIn_reg <= (datIn_reg<<4)|(datOut_active[2] ? 4'b1111 : {datIn[3], datIn[2], datIn[1], datIn[0]});
        datIn_counter <= datIn_counter-1;
        datIn_crcCounter <= datIn_crcCounter-1;
        datIn_crcRst <= 0;
        datIn_crcEn <= 0;
        
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
            resp_counter <= (cmd_respType===`SDController_RespType_48 ? 48-8-1 : 136-8-1);
            // Wait for response to start
            if (!resp_staged) begin
                $display("[SD-CTRL:RESP] Triggered");
                resp_state <= 2;
            end
        end
        
        2: begin
            resp_crcEn <= 1;
            if (!resp_counter) begin
                resp_state <= 3;
            end
        end
        
        3: begin
            resp_counter <= 6;
            resp_state <= 4;
        end
        
        4: begin
            if (resp_crc === cmdresp_shiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good CRC bit (ours: %b, theirs: %b) ✅", resp_crc, cmdresp_shiftReg[1]);
            end else begin
`ifdef SIM
                if (cmd_data[45:40] !== 6'd2) begin
                    $display("[SD-CTRL:RESP] Response: Bad CRC bit (ours: %b, theirs: %b) ❌", resp_crc, cmdresp_shiftReg[1]);
                    `Finish;
                end else begin
                    $display("[SD-CTRL:RESP] Response: Bad CRC bit (ours: %b, theirs: %b); ignoring because it's a CMD2 response",
                        resp_crc, cmdresp_shiftReg[1]);
                end
`endif
                resp_crcErr <= 1;
            end
            
            if (!resp_counter) begin
                resp_data <= cmdresp_shiftReg;
                resp_state <= 5;
            end
        end
        
        5: begin
            if (cmdresp_shiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good end bit ✅");
            end else begin
                $display("[SD-CTRL:RESP] Response: Bad end bit ❌");
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
        end
        
        1: begin
            $display("[SD-CTRL:DATOUT] Write session starting");
            // Reset the FIFO
            datOutFIFO_rst <= !datOutFIFO_rst;
            datOut_crcErr <= 0;
            datOut_state <= 2;
        end
        
        2: begin
            // Wait for the FIFO to finish resetting
            if (datOut_fifoRstDone) begin
                $display("[SD-CTRL:DATOUT] Signalling ready");
                datOut_ready <= !datOut_ready;
                datOut_state <= 3;
            end
        end
        
        3: begin
            // Wait for data to start
            if (datOutFIFO_readReady) begin
                datOut_state <= 4;
            end
        end
        
        4: begin
            $display("[SD-CTRL:DATOUT] Write another block");
            datOut_counter <= 0;
            datOut_ending <= 0;
            datOut_crcRst <= 1;
            datOut_startBit <= 1;
            datOut_state <= 5;
        end
        
        5: begin
            datOut_active[0] <= 1;
            datOut_crcEn <= 1;
            
            if (!datOut_counter) begin
                // $display("[SD-CTRL:DATOUT]   Write another word: %x", datOutFIFO_readData);
                datOutFIFO_readTrigger <= 1;
            end
            
            if (datOut_ending) begin
                $display("[SD-CTRL:DATOUT] Done writing");
                datOut_state <= 6;
            end
        end
        
        // Output the CRC
        6: begin
            datOut_active[0] <= 1;
            datOut_crcEn <= 1;
            datOut_crcOutEn <= 1;
            datOut_crcCounter <= 15;
            datOut_state <= 7;
        end
        
        // Wait for CRC output to finish
        7: begin
            datOut_active[0] <= 1;
            if (datOut_crcCounter) begin
                datOut_crcOutEn <= 1;
            end else begin
                datOut_endBit <= 1;
                datOut_state <= 8;
            end
        end
        
        // Output the end bit
        8: begin
            datOut_active[0] <= 1;
            datOut_state <= 9;
        end
        
        // Wait for the CRC status from the card
        9: begin
            if (!datIn_reg[16]) begin
                datOut_state <= 10;
            end
        end
        
        // Check CRC status token
        10: begin
            $display("[SD-CTRL:DATOUT] DatOut: datOut_crcStatusOKReg: %b", datOut_crcStatusOKReg);
            // 5 bits: start bit, CRC status, end bit
            if (datOut_crcStatusOKReg) begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status valid ✅");
            end else begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status invalid: %b ❌", datOut_crcStatusOKReg);
                `Finish;
                datOut_crcErr <= 1;
            end
            datOut_state <= 11;
        end
        
        // Wait until the card stops being busy (busy == DAT0 low)
        11: begin
            if (datIn_reg[0]) begin
                $display("[SD-CTRL:DATOUT] Card ready");
                // `Finish;
                
                if (datOutFIFO_readReady) begin
                    datOut_state <= 4;
                
                end else begin
                    datOut_done <= !datOut_done;
                    datOut_state <= 0;
                end
            
            end else begin
                $display("[SD-CTRL:DATOUT] Card busy");
            end
        end
        endcase
        
        if (datOut_startPulse) begin
            datOut_state <= 1;
        end
        
        // ====================
        // DatIn State Machine
        // ====================
        case (datIn_state)
        0: begin
        end
        
        1: begin
            datIn_crcRst <= 1;
            datIn_crcErr <= 0;
            datIn_state <= 2;
        end
        
        2: begin
            datIn_counter <= 127;
            if (!datIn_reg[0]) begin
                $display("[SD-CTRL:DATIN] Triggered");
                datIn_state <= 3;
            end
        end
        
        3: begin
            datIn_crcEn <= 1;
            // Stash the access mode from the DatIn response.
            // (This assumes we're receiving a CMD6 response.)
            if (datIn_counter === 7'd94) begin
                datIn_cmd6AccessMode <= datIn_reg[3:0];
            end
            
            // Stay in this state until datIn_counter==0
            if (!datIn_counter) begin
                datIn_state <= 4;
            end
        end
        
        4: begin
            datIn_crcCounter <= 15;
            datIn_state <= 5;
        end
        
        5: begin
            if (datIn_crc[3] === datIn_reg[7]) begin
                $display("[SD-CTRL:DATIN] DAT3 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT3 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[3], datIn_reg[7]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (datIn_crc[2] === datIn_reg[6]) begin
                $display("[SD-CTRL:DATIN] DAT2 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT2 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[2], datIn_reg[6]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (datIn_crc[1] === datIn_reg[5]) begin
                $display("[SD-CTRL:DATIN] DAT1 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT1 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[1], datIn_reg[5]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (datIn_crc[0] === datIn_reg[4]) begin
                $display("[SD-CTRL:DATIN] DAT0 CRC valid ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad DAT0 CRC ❌ (ours: %b, theirs: %b)", datIn_crc[0], datIn_reg[4]);
                `Finish;
                datIn_crcErr <= 1;
            end
            
            if (!datIn_crcCounter) begin
                datIn_state <= 6;
            end
        end
        
        6: begin
            if (datIn_reg[7:4] === 4'b1111) begin
                $display("[SD-CTRL:DATIN] Good end bit ✅");
            end else begin
                $display("[SD-CTRL:DATIN] Bad end bit ❌");
                `Finish;
                datIn_crcErr <= 1;
            end
            // Signal that the DatIn is complete
            datIn_done <= !datIn_done;
            datIn_state <= 0;
        end
        endcase
        
        // ====================
        // CmdOut State Machine
        //   This needs to be below the Resp/DatOut/DatIn state machines, so that the Cmd
        //   assignments take precedence (such as when assigning resp_state/datIn_state.)
        // ====================
        case (cmd_state)
        0: begin
        end
        
        1: begin
            $display("[SD-CTRL:CMD] Triggered");
            // Reset Resp/DatIn state machines
            resp_state <= 0;
            datIn_state <= 0;
            cmd_crcRst <= 1;
            cmd_state <= 2;
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
            $display("[SD-CTRL:CMD] Done");
            cmd_done <= !cmd_done;
            if (cmd_respType!==`SDController_RespType_None) resp_state <= 1;
            if (cmd_datInType!==`SDController_DatInType_None) datIn_state <= 1;
            cmd_state <= 0;
        end
        endcase
        
        if (cmd_triggerPulse) begin
            cmd_state <= 1;
        end
    end
    
    // ====================
    // Dat Out FIFO
    // ====================
    BankFIFO #(
        .W(16),
        .N(8)
    ) BankFIFO (
        .rst(datOutFIFO_rst),
        .rst_done(datOutFIFO_rstDone),
        
        .w_clk(datOutWrite_clk),
        .w_ready(datOutWrite_ready),
        .w_trigger(datOutWrite_trigger),
        .w_data(datOutWrite_data),
        
        .r_clk(clk_int),
        .r_ready(datOutFIFO_readReady),
        .r_trigger(datOutFIFO_readTrigger),
        .r_data(datOutFIFO_readData),
        .r_bank(datOutFIFO_readBank)
    );
    
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
            .Delay(0)
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
