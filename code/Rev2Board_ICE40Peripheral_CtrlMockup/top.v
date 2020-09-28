`include "../Util.v"
`include "../Sync.v"
`include "../TogglePulse.v"
`include "../ToggleAck.v"
`include "../ClockGen.v"
`include "../MsgChannel.v"
`include "../CRC7.v"
`include "../CRC16.v"
`include "../BankFifo.v"
`include "../Delay.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`ifdef SIM
`include "../SDCardSim.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          clk12mhz,
    
    input wire          ctrl_clk,
    input wire          ctrl_di,
    output wire         ctrl_do,
    
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat
);
    // ====================
    // Shared Nets/Registers
    // ====================
    reg ctrl_sdClkFast = 0;
    reg ctrl_sdClkSlow = 0;
    reg ctrl_sdCmdOutTrigger = 0;
    reg ctrl_sdDatOutTrigger = 0;
    reg[65:0] ctrl_dinReg = 0;
    wire[55:0] ctrl_msgArg = ctrl_dinReg[56:1];
    wire[7:0] ctrl_msgCmd = ctrl_dinReg[64:57];
    
    // ====================
    // Fast Clock (207 MHz)
    // ====================
    localparam FastClkFreq = 207_000_000;
    wire fastClk;
    ClockGen #(
        .FREQ(FastClkFreq),
        .DIVR(0),
        .DIVF(68),
        .DIVQ(2),
        .FILTER_RANGE(1)
    ) ClockGen_fastClk(.clk12mhz(clk12mhz), .clk(fastClk));
    
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
    
    // ====================
    // sd_clk
    //   Delay `sd_clk` relative to `sd_clk_int` to correct the phase from the SD card's perspective
    // ====================
    Delay #(
        .Count(3)
    ) Delay_sd_clk_int(
        .in(sd_clk_int),
        .out(sd_clk)
    );
    
    // ====================
    // w_clk
    // ====================
    localparam WClkFreq = 96_000_000;
    wire w_clk;
    ClockGen #(
        .FREQ(WClkFreq),
        .DIVR(0),
        .DIVF(63),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_w_clk(.clk12mhz(clk12mhz), .clk(w_clk));
    
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
            if (w_counter === 'h7FE) begin
`else
            if (w_counter === 'h7FFFFE) begin
`endif
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
    reg[2:0] sd_datOutState = 0;
    
    reg[47:0] sd_shiftReg = 0;
    
    reg sd_cmdOutCRCEn = 0;
    reg sd_cmdOutCRCOutEn = 0;
    reg sd_cmdOutDone = 0;
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
    
    reg sd_datOutActive = 0;
    reg sd_datOutCRCEn = 0;
    reg sd_datOutCRCErr = 0;
    reg sd_datOutCRCOutEn = 0;
    reg sd_datOutEndBit = 0;
    reg sd_datOutEnding = 0;
    reg sd_datOutLastBank = 0;
    reg sd_datOutStartBit = 0;
    reg[19:0] sd_datInReg = 0;
    reg[19:0] sd_datOutReg = 0;
    reg[1:0] sd_datOutCounter = 0;
    reg[3:0] sd_datOutCRCCounter = 0;
    wire[3:0] sd_datIn;
    wire[3:0] sd_datOutCRC;
    wire[4:0] sd_datInCRCStatus = {sd_datInReg[16], sd_datInReg[12], sd_datInReg[8], sd_datInReg[4], sd_datInReg[0]};
    wire sd_datInCRCStatusOK = sd_datInCRCStatus===5'b0_010_1; // 5 bits: start bit, CRC status, end bit
    reg sd_datInCRCStatusReg = 0;
    reg[1:0] sd_datOutIdleReg = 0; // 2 bits -- see explanation where it's assigned
    
    `TogglePulse(sd_cmdOutTrigger, ctrl_sdCmdOutTrigger, posedge, sd_clk_int);
    
    always @(posedge sd_clk_int) begin
        // ====================
        // CmdOut State Machine
        // ====================
        sd_cmdOutState <= sd_cmdOutState>>1;
        sd_cmdOutState[11] <= (!sd_cmdOutStateInit)|sd_cmdOutState[0];
        sd_cmdOutStateInit <= 1;
        sd_cmdOutCounter <= sd_cmdOutCounter-1;
        // `sd_cmdOutActive` is 3 bits to track whether `sd_cmdIn` is
        // valid or not, since it takes several cycles to transition
        // between output and input.
        sd_cmdOutActive <= (sd_cmdOutActive<<1)|sd_cmdOutActive[0];
        
        sd_shiftReg <= sd_shiftReg<<1|sd_respStaged;
        if (sd_cmdOutCRCOutEn)  sd_shiftReg[47] <= sd_cmdOutCRC;
        
        if (sd_cmdOutState[11]) begin
            sd_cmdOutActive[0] <= 0;
            sd_cmdOutCounter <= 38;
            if (sd_cmdOutTrigger) begin
                $display("[SD-CTRL:CMDOUT] Command to be clocked out: %b", ctrl_msgArg[47:0]);
            end else begin
                // Stay in this state
                sd_cmdOutState[11:10] <= sd_cmdOutState[11:10];
            end
        end
        
        if (sd_cmdOutState[10]) begin
            sd_cmdOutActive[0] <= 1;
            sd_shiftReg <= ctrl_msgArg;
            sd_cmdOutCRCEn <= 1;
        end
        
        if (sd_cmdOutState[9]) begin
            if (sd_cmdOutCounter) begin
                // Stay in this state
                sd_cmdOutState[9:8] <= sd_cmdOutState[9:8];
            end
        end
        
        if (sd_cmdOutState[8]) begin
            sd_cmdOutCRCOutEn <= 1;
        end
        
        if (sd_cmdOutState[7]) begin
            sd_cmdOutCRCEn <= 0;
        end
        
        if (sd_cmdOutState[1]) begin
            sd_cmdOutCRCOutEn <= 0;
            sd_cmdOutDone <= !sd_cmdOutDone;
            sd_respGo <= 1;
        end
        
        
        
        // ====================
        // Resp State Machine
        // ====================
        sd_respState <= sd_respState>>1;
        sd_respState[9] <= (!sd_respStateInit)|sd_respState[0];
        sd_respStateInit <= 1;
        sd_respStaged <= sd_cmdOutActive[2] ? 1'b1 : sd_cmdIn;
        
        if (sd_respState[9]) begin
            sd_respCRCEn <= 0;
            sd_respCRCErr <= 0;
            if (sd_respGo && !sd_respStaged) begin
                sd_respCRCEn <= 1;
            end else begin
                // Stay in this state
                sd_respState[9:8] <= sd_respState[9:8];
            end
        end
        
        if (sd_respState[8]) begin
            if (!sd_shiftReg[40]) begin
                sd_respCRCEn <= 0;
            end else begin
                sd_respState[8:7] <= sd_respState[8:7];
            end
        end
        
        if (sd_respState[7:1]) begin
            if (sd_respCRC === sd_shiftReg[1]) begin
                $display("[SD-CTRL:RESP] Response: Good CRC bit (ours: %b, theirs: %b) ✅", sd_respCRC, sd_shiftReg[1]);
            end else begin
                sd_respCRCErr <= sd_respCRCErr|1;
                $display("[SD-CTRL:RESP] Response: Bad CRC bit (ours: %b, theirs: %b) ❌", sd_respCRC, sd_shiftReg[1]);
                // `Finish;
            end
        end
        
        if (sd_respState[1]) begin
            sd_respGo <= 0;
        end
        
        if (sd_respState[0]) begin
            sd_resp <= sd_shiftReg>>1;
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
        sd_datInReg <= (sd_datInReg<<4)|{sd_datIn[3], sd_datIn[2], sd_datIn[1], sd_datIn[0]};
        sd_datInCRCStatusReg <= sd_datInCRCStatusReg<<1|sd_datInCRCStatusOK;
        sd_datOutReg <= sd_datOutReg<<4;
        if (!sd_datOutCounter)  sd_datOutReg[15:0] <= sd_datOutFifo_rdata;
        if (sd_datOutCRCOutEn)  sd_datOutReg[19:16] <= sd_datOutCRC;
        if (sd_datOutStartBit)  sd_datOutReg[19:16] <= 4'b0000;
        if (sd_datOutEndBit)    sd_datOutReg[19:16] <= 4'b1111;
        
        case (sd_datOutState)
        0: begin
            sd_datOutCounter <= 0;
            sd_datOutCRCCounter <= 0;
            sd_datOutActive <= 0;
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
            sd_datOutActive <= 1;
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
            // $display("meowmix sd_datOutCRCCounter: %0d", sd_datOutCRCCounter);
            sd_datOutCRCOutEn <= 0;
            if (sd_datOutCRCCounter === 14) begin
                sd_datOutActive <= 0;
            end
            
            if (sd_datOutCRCCounter === 4) begin
                sd_datOutState <= 5;
            end
        end
        
        // Wait until the card stops being busy (busy == DAT0 low)
        5: begin
            $display("[SD-CTRL:DATOUT] DatOut: sd_datInCRCStatusReg: %b", sd_datInCRCStatusReg);
            // 5 bits: start bit, CRC status, end bit
            if (sd_datInCRCStatusReg) begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status valid ✅");
            end else begin
                $display("[SD-CTRL:DATOUT] DatOut: CRC status invalid: %b ❌", sd_datInCRCStatusReg);
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
    end
    
    
    
    
    
    
    // ====================
    // Control State Machine
    // ====================
    localparam Msg_StartBit = 1'b0;
    localparam Msg_EndBit   = 1'b1;
    
    localparam MsgCmd_Echo              = 8'h00;
    localparam MsgCmd_SDSetClkSrc       = 8'h01;
    localparam MsgCmd_SDSendCmd         = 8'h02;
    localparam MsgCmd_SDGetStatus       = 8'h03;
    localparam MsgCmd_SDDatOut          = 8'h04;
    
    reg[1:0] ctrl_state = 0;
    reg[6:0] ctrl_counter = 0;
    reg ctrl_dinActive = 0;
    reg[65:0] ctrl_doutReg = 0;
    
    wire sd_datOutIdle = &sd_datOutIdleReg;
    `ToggleAck(ctrl_sdCmdOutDone, ctrl_sdCmdOutDoneAck, sd_cmdOutDone, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdRespRecv, ctrl_sdRespRecvAck, sd_respRecv, posedge, ctrl_clk);
    `Sync(ctrl_sdDatOutIdle, sd_datOutIdle, posedge, ctrl_clk);
    `Sync(ctrl_sdRespCRCErr, sd_respCRCErr, posedge, ctrl_clk);
    `Sync(ctrl_sdDatOutCRCErr, sd_datOutCRCErr, posedge, ctrl_clk);
    
    always @(posedge ctrl_clk) begin
        if (ctrl_dinActive) ctrl_dinReg <= ctrl_dinReg<<1|ctrlDI;
        ctrl_counter <= ctrl_counter-1;
        ctrl_doutReg <= ctrl_doutReg<<1|1'b1;
        
        case (ctrl_state)
        0: begin
            ctrl_counter <= 64;
            if (!ctrlDI) begin
                ctrl_dinActive <= 1;
                ctrl_state <= 1;
            end
        end
        
        1: begin
            if (!ctrl_counter) begin
                ctrl_dinActive <= 0;
                ctrl_state <= 2;
            end
        end
        
        2: begin
            // $display("[CTRL] Got command: %b [cmd: %0d, arg: %0d]", ctrl_dinReg, ctrl_msgCmd, ctrl_msgArg);
            case (ctrl_msgCmd)
            // Echo
            MsgCmd_Echo: begin
                ctrl_doutReg <= {Msg_StartBit, ctrl_msgArg, 8'b0, Msg_EndBit};
            end
            
            // Set SD clock source
            MsgCmd_SDSetClkSrc: begin
                $display("[CTRL] Got SDSetClkSrc: %0d", ctrl_msgArg[1:0]);
                ctrl_sdClkSlow <= ctrl_msgArg[0];
                ctrl_sdClkFast <= ctrl_msgArg[1];
            end
            
            // Clock out SD command
            MsgCmd_SDSendCmd: begin
                $display("[CTRL] Got SDSendCmd");
                // Clear our signals so they can be reliably observed via SDGetStatus
                if (ctrl_sdCmdOutDone) ctrl_sdCmdOutDoneAck <= !ctrl_sdCmdOutDoneAck;
                if (ctrl_sdRespRecv) ctrl_sdRespRecvAck <= !ctrl_sdRespRecvAck;
                ctrl_sdCmdOutTrigger <= !ctrl_sdCmdOutTrigger;
            end
            
            // Get SD status / response
            MsgCmd_SDGetStatus: begin
                // $display("[CTRL] Got MsgCmd_SDGetStatus");
                // We don't need a synchronizer for sd_resp because
                // it's guarded by `ctrl_sdRespRecv`, which is synchronized.
                // Ie, sd_resp should be ignored unless ctrl_sdRespRecv=1.
                // TODO: add a synchronizer for `sd_datIn`
                ctrl_doutReg <=
                    {Msg_StartBit,
                        sd_datIn,               // 63:60
                        ctrl_sdCmdOutDone,      // 59
                        ctrl_sdRespRecv,        // 58
                        ctrl_sdDatOutIdle,      // 57
                        
                        ctrl_sdRespCRCErr,      // 56       Reset every SD response (since some responses have incorrect CRCs, like ACMD41)
                        ctrl_sdDatOutCRCErr,    // 55       Accumulates, never reset
                        
                        7'b0,                   // 54:48
                        sd_resp,                // 47:0
                    Msg_EndBit};
            end
            
            MsgCmd_SDDatOut: begin
                ctrl_sdDatOutTrigger <= !ctrl_sdDatOutTrigger;
            end
            endcase
            
            ctrl_state <= 0;
        end
        endcase
    end
    
    // ====================
    // Pin: ctrl_di
    // ====================
    wire ctrlDI;
    SB_IO #(
        .PIN_TYPE(6'b0000_00),
        .PULLUP(1'b1)
    ) SB_IO_ctrl_clk (
        .INPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_di),
        .D_IN_0(ctrlDI)
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
        .D_OUT_0(ctrl_doutReg[65])
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
        .D_OUT_0(sd_shiftReg[47]),
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
            .OUTPUT_ENABLE(sd_datOutActive),
            .D_OUT_0(sd_datOutReg[16+i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    // ====================
    // CRC: sd_cmdOutCRC
    // ====================
    CRC7 #(
        .Delay(-1)
    ) CRC7_sd_cmdOut(
        .clk(sd_clk_int),
        .en(sd_cmdOutCRCEn),
        .din(sd_shiftReg[47]),
        .dout(sd_cmdOutCRC)
    );
    
    // ====================
    // CRC: sd_cmdOutCRC
    // ====================
    CRC7 #(
        .Delay(1)
    ) CRC7_sd_resp(
        .clk(sd_clk_int),
        .en(sd_respCRCEn),
        .din(sd_shiftReg[0]),
        .dout(sd_respCRC)
    );
    
    // ====================
    // CRC: sd_datOutCRC
    // ====================
    for (i=0; i<4; i=i+1) begin
        CRC16 #(
            .Delay(-1)
        ) CRC16_dat(
            .clk(sd_clk_int),
            .en(sd_datOutCRCEn),
            .din(sd_datOutReg[16+i]),
            .dout(sd_datOutCRC[i])
        );
    end
endmodule







`ifdef SIM
module Testbench();
    reg         clk12mhz;
    
    reg         ctrl_clk;
    tri1        ctrl_di;
    tri1        ctrl_do;
    
    wire        sd_clk;
    tri1        sd_cmd;
    tri1[3:0]   sd_dat;
    
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
            clk12mhz = 0;
            #42;
            clk12mhz = 1;
            #42;
        end
    end
    
    initial begin
        forever begin
            ctrl_clk = 0;
            #42;
            ctrl_clk = 1;
            #42;
        end
    end
    
    localparam START_BIT    = 1'b0;
    localparam END_BIT      = 1'b1;
    
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
    
    reg[65:0] ctrl_diReg;
    reg[65:0] ctrl_doReg;
    wire[63:0] ctrl_doReg_payload = ctrl_doReg[64:1];
    reg[63:0] resp;
    
    always @(posedge ctrl_clk) begin
        ctrl_diReg <= ctrl_diReg<<1|1'b1;
        ctrl_doReg <= ctrl_doReg<<1|ctrl_do;
    end
    
    assign ctrl_di = ctrl_diReg[65];
    
    task _SendMsg(input[63:0] msg); begin
        reg[15:0] i;
        
        ctrl_diReg = {START_BIT, msg, END_BIT};
        for (i=0; i<66; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
    end endtask
    
    task SendMsg(input[63:0] msg); begin
        reg[15:0] i;
        
        _SendMsg(msg);
        
        // Wait for msg to be consumed before sending another, otherwise we can overwrite
        // the shift register while it's still being used
        #100000;
        wait(!ctrl_clk);
    end endtask
    
    task SendMsgRecvResp(input[63:0] msg); begin
        reg[15:0] i;
        
        _SendMsg(msg);
        
        // Wait for response to start
        while (ctrl_doReg[0]) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        // Load the full response
        for (i=0; i<65; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        resp = ctrl_doReg_payload;
    end endtask
    
    task SendSDCmd(input[5:0] sdCmd, input[31:0] sdArg); begin
        SendMsg({8'd2, 8'b0, {2'b01, sdCmd, sdArg, 7'b0, 1'b1}});
        
        // Wait for SD card to respond
        do begin
            // Request SD status
            SendMsgRecvResp({8'd3, 56'b0});
        end while(!resp[58]);
    end endtask
    
    initial begin
        reg[15:0] i, ii;
        reg sdDone;
        ctrl_diReg = ~0;
        
        wait(ctrl_clk);
        wait(!ctrl_clk);
        
        // // Disable SD clock
        // SendMsg({8'd1, 56'b00});
        //
        // // Set SD clock source = fast clock
        // SendMsg({8'd1, 56'b10});
        //
        // SendSDCmd(CMD55, 32'b0);
        
        
        
        // Disable SD clock
        SendMsg({8'd1, 56'b00});
        
        // Set SD clock source = fast clock
        SendMsg({8'd1, 56'b10});
        
        // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        SendSDCmd(CMD55, 32'b0);
        SendSDCmd(ACMD23, 32'b1);
        
        // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        SendSDCmd(CMD25, 32'b0);
        
        // Clock out data on DAT lines
        SendMsg({8'd4, 56'b0});
        
        // Wait some pre-determined amount of time that guarantees
        // that we've started writing to the SD card.
        for (i=0; i<64; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        // Wait until we're done clocking out data on DAT lines
        $display("[EXT] Waiting while data is written...");
        do begin
            // Request SD status
            SendMsgRecvResp({8'd3, 56'b0});
        end while(!resp[57]);
        $display("[EXT] Done writing");
        
        // Check CRC status
        if (resp[55] === 1'b0) begin
            $display("[EXT] CRC OK ✅");
        end else begin
            $display("[EXT] CRC bad ❌");
        end
    end
endmodule
`endif
