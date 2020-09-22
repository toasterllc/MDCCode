`include "../Util.v"
`include "../ClockGen.v"
`include "../MsgChannel.v"
`include "../CRC7.v"
`include "../CRC16.v"
`include "../AFIFO.v"
`include "../BankFifo.v"

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
    function [63:0] DivCeil;
        input [63:0] n;
        input [63:0] d;
        begin
            DivCeil = (n+d-1)/d;
        end
    endfunction
    
    
    
    // ====================
    // Registers
    // ====================
    reg[47:0] sd_shiftReg = 0;
    reg[2:0] sd_cmdOutActive = 0;
    wire[6:0] sd_cmdOutCRC;
    reg sd_cmdOutCRCRst_ = 0;
    wire[6:0] sd_respCRC;
    reg[6:0] sd_respExpectedCRC = 0;
    reg sd_respCRCRst_ = 0;
    
    wire[3:0] sd_datIn;
    reg[3:0] sd_datOut = 0;
    reg sd_datOutActive = 0;
    
    wire sd_cmdIn;
    reg[47:0] sd_resp = 0;
    reg sd_cmdOutDone = 0;
    reg sd_respReady = 0;
    reg sd_respCRCOK = 0;
    
    reg[5:0] sd_counter = 0;
    reg[1:0] sd_datOutCounter = 0;
    reg sd_datOutLastBank = 0;
    reg sd_datOutEnding = 0;
    
    reg ctrl_dinActive = 0;
    reg[65:0] ctrl_dinReg = 0;
    wire[7:0] ctrl_msgCmd = ctrl_dinReg[64:57];
    wire[55:0] ctrl_msgArg = ctrl_dinReg[56:1];
    
    reg[65:0] ctrl_doutReg = 0;
    
    reg[6:0] ctrl_counter = 0;
    reg ctrl_sdClkSlow = 0;
    reg ctrl_sdClkFast = 0;
    
    reg ctrl_sdCmdOutTrigger = 0;
    reg ctrl_sdDatOutTrigger = 0;
    
    
    // // ====================
    // // Fast Clock (204 MHz)
    // // ====================
    // wire fastClk;
    // ClockGen #(
    //     .FREQ(204000000),
    //     .DIVR(0),
    //     .DIVF(67),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(fastClk));
    
    
    // // ====================
    // // Fast Clock (180 MHz)
    // // ====================
    // wire fastClk;
    // ClockGen #(
    //     .FREQ(180000000),
    //     .DIVR(0),
    //     .DIVF(59),
    //     .DIVQ(2),
    //     .FILTER_RANGE(1)
    // ) ClockGen(.clk12mhz(clk12mhz), .clk(fastClk));
    
    // ====================
    // Fast Clock (120 MHz)
    // ====================
    wire fastClk;
    ClockGen #(
        .FREQ(120000000),
        .DIVR(0),
        .DIVF(79),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen(.clk12mhz(clk12mhz), .clk(fastClk));
    
    
    // ====================
    // Slow Clock (400 kHz)
    // ====================
    localparam SlowClkFreq = 400000;
    localparam SlowClkDividerWidth = $clog2(DivCeil(180000000, SlowClkFreq));
    reg[SlowClkDividerWidth-1:0] slowClkDivider = 0;
    wire slowClk = slowClkDivider[SlowClkDividerWidth-1];
    always @(posedge fastClk) begin
        slowClkDivider <= slowClkDivider+1;
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
    // Pin: sd_clk
    // ====================
    reg sdClkSlow=0, sdClkSlowTmp=0;
    always @(negedge slowClk)
        {sdClkSlow, sdClkSlowTmp} <= {sdClkSlowTmp, ctrl_sdClkSlow};
    
    reg sdClkFast=0, sdClkFastTmp=0;
    always @(negedge fastClk)
        {sdClkFast, sdClkFastTmp} <= {sdClkFastTmp, ctrl_sdClkFast};
    
    assign sd_clk = (sdClkSlow ? slowClk : (sdClkFast ? fastClk : 0));
    
    
    
    // ====================
    // Pin: sd_cmd
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00)
    ) SB_IO_sd_clk (
        .INPUT_CLK(sd_clk),
        .OUTPUT_CLK(sd_clk),
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
            .INPUT_CLK(sd_clk),
            .OUTPUT_CLK(sd_clk),
            .PACKAGE_PIN(sd_dat[i]),
            .OUTPUT_ENABLE(sd_datOutActive),
            .D_OUT_0(sd_datOut[i]),
            .D_IN_0(sd_datIn[i])
        );
    end
    
    
    
    
    // ====================
    // CRC
    // ====================
    CRC7 CRC7_sd_cmdOut(
        .clk(sd_clk),
        .rst_(sd_cmdOutCRCRst_),
        .din(sd_shiftReg[47]),
        .doutNext(sd_cmdOutCRC)
    );
    
    CRC7 CRC7_sd_resp(
        .clk(sd_clk),
        .rst_(sd_respCRCRst_),
        .din(sd_shiftReg[0]),
        .dout(sd_respCRC)
    );
    
    wire[15:0] datCRC[3:0];
    reg datCRCRst_ = 0;
    // genvar i;
    for (i=0; i<4; i=i+1) begin
        CRC16 CRC16_dat(
            .clk(clk),
            .rst_(datCRCRst_),
            .din(sd_memReg[0+i]),
            .dout(),
            .doutNext(datCRC[i])
        );
    end
    
    
    
    
    
    // ====================
    // FIFO
    // ====================
    reg w_sdDatOutFifo_wtrigger = 0;
    reg[7:0] w_sdDatOutFifo_wdata = 0;
    wire w_sdDatOutFifo_wok;
    
    reg sd_sdDatOutFifo_rtrigger = 0;
    wire[15:0] sd_sdDatOutFifo_rdata;
    wire sd_sdDatOutFifo_rok;
    BankFifo #(
        .W(16),
        .N(8)
    ) BankFifo_sdDatOut(
        .w_clk(clk12mhz),
        .w_trigger(w_sdDatOutFifo_wtrigger),
        .w_data({w_sdDatOutFifo_wdata, w_sdDatOutFifo_wdata}),
        .w_ok(w_sdDatOutFifo_wok),
        
        .r_clk(sd_clk),
        .r_trigger(sd_sdDatOutFifo_rtrigger),
        .r_data(sd_sdDatOutFifo_rdata),
        .r_ok(sd_sdDatOutFifo_rok),
        .r_bank(sd_sdDatOutFifo_rbank)
    );
    
    
    
    
    reg[2:0] sd_cmdOutTriggerTmp = 0;
    wire sd_cmdOutTrigger = sd_cmdOutTriggerTmp[2]!==sd_cmdOutTriggerTmp[1];
    always @(posedge sd_clk)
        sd_cmdOutTriggerTmp <= (sd_cmdOutTriggerTmp<<1)|ctrl_sdCmdOutTrigger;
    
    reg[2:0] w_sdDatOutTriggerTmp = 0;
    wire w_sdDatOutTrigger = w_sdDatOutTriggerTmp[2]!==w_sdDatOutTriggerTmp[1];
    always @(posedge clk12mhz)
        w_sdDatOutTriggerTmp <= (w_sdDatOutTriggerTmp<<1)|ctrl_sdDatOutTrigger;
    
    reg[1:0] w_state = 0;
    always @(posedge clk12mhz) begin
        case (w_state)
        0: begin
            w_sdDatOutFifo_wtrigger <= 0;
            // w_sdDatOutFifo_wdata <= 0;
            if (w_sdDatOutTrigger) begin
                w_state <= 1;
            end
        end
        
        1: begin
            w_sdDatOutFifo_wtrigger <= 1;
            w_sdDatOutFifo_wdata <= 8'hFF;
            // w_sdDatOutFifo_wdata <= w_sdDatOutFifo_wdata+1;
            // if (w_sdDatOutFifo_wdata === 8'hFF) begin
            //     w_state <= 0;
            // end
        end
        endcase
    end
    
    // ====================
    // SD State Machine
    // ====================
    
    reg[15:0] sd_memReg = 0;
    reg[1:0] sd_datOutState = 0;
    reg[1:0] sd_respState = 0;
    reg[1:0] sd_cmdOutState = 0;
    wire sd_cmdInStaged = (sd_cmdOutActive[2] ? 1'b1 : sd_cmdIn);
    
    reg[2:0] sd_datOutTriggerTmp = 0;
    wire sd_datOutTrigger = sd_datOutTriggerTmp[2]!==sd_datOutTriggerTmp[1];
    always @(posedge sd_clk)
        sd_datOutTriggerTmp <= (sd_datOutTriggerTmp<<1)|ctrl_sdDatOutTrigger;
    
    always @(posedge sd_clk) begin
        sd_shiftReg <= (sd_shiftReg<<1)|sd_cmdInStaged;
        sd_counter <= sd_counter-1;
        sd_datOutCounter <= sd_datOutCounter-1;
        sd_cmdOutActive <= (sd_cmdOutActive<<1)|sd_cmdOutActive[0];
        sd_respExpectedCRC <= sd_respExpectedCRC<<1;
        sd_memReg <= sd_memReg>>4;
        sd_datOut <= sd_memReg[3:0];
        sd_sdDatOutFifo_rtrigger <= 0; // Pulse
        sd_datOutLastBank <= sd_sdDatOutFifo_rbank;
        sd_datOutEnding <= sd_datOutEnding|(sd_datOutLastBank && !sd_sdDatOutFifo_rbank);
        
        if (!sd_datOutCounter) begin
            sd_memReg <= sd_sdDatOutFifo_rdata;
        end
        
        case (sd_datOutState)
        0: begin
            sd_datOutCounter <= 0;
            sd_datOutActive <= 0;
            sd_datOutEnding <= 0;
            datCRCRst_ <= 0;
            if (sd_sdDatOutFifo_rok) begin
                $display("[SD DATOUT] Write another block to SD card");
                datCRCRst_ <= 1;
                sd_datOutState <= 1;
            end
        end
        
        1: begin
            sd_datOutActive <= 1;
            
            if (!sd_datOutCounter) begin
                if (!sd_datOutEnding) begin
                    $display("[SD DATOUT]   Write another word: %x", sd_sdDatOutFifo_rdata);
                    sd_sdDatOutFifo_rtrigger <= 1;
                
                end else begin
                    $display("[SD DATOUT] Done writing (sd_datOutCounter: %x)", sd_datOutCounter);
                    sd_datOutState <= 2;
                end
            end
        end
        
        2: begin
            
        end
        endcase
        
        
        
        
        
        case (sd_respState)
        0: begin
        end
        
        1: begin
            sd_respCRCRst_ <= 0;
            sd_respCRCOK <= 1;
            if (!sd_cmdInStaged) begin
                sd_respCRCRst_ <= 1;
                sd_respState <= 2;
            end
        end
        
        2: begin
            if (!sd_shiftReg[40]) begin
                sd_respExpectedCRC <= sd_respCRC;
                sd_respState <= 3;
            end
        end
        
        3: begin
            if (sd_respExpectedCRC[6] === sd_shiftReg[1]) begin
                $display("[CTRL] Response: Good CRC bit (wanted: %b, got: %b) ✅", sd_respExpectedCRC[6], sd_shiftReg[1]);
            end else begin
                sd_respCRCOK <= 0;
                $display("[CTRL] Response: Bad CRC bit (wanted: %b, got: %b) ❌", sd_respExpectedCRC[6], sd_shiftReg[1]);
                // `finish;
            end
            
            if (!sd_shiftReg[47]) begin
                sd_resp <= sd_shiftReg;
                sd_respReady <= 1;
                sd_respState <= 0;
            end
        end
        endcase
        
        
        
        
        
        
        case (sd_cmdOutState)
        0: begin
            if (sd_cmdOutTrigger) begin
                sd_cmdOutActive[0] <= 1;
                sd_shiftReg <= ctrl_msgArg;
                sd_counter <= 47;
                sd_cmdOutCRCRst_ <= 1;
                sd_respState <= 0;
                sd_cmdOutDone <= 0;
                sd_respReady <= 0;
                sd_cmdOutState <= 1;
            end
        end
        
        1: begin
            if (sd_counter === 8) begin
                sd_shiftReg[47:41] <= sd_cmdOutCRC;
            end
            
            if (!sd_counter) begin
                sd_cmdOutActive[0] <= 0;
                sd_cmdOutCRCRst_ <= 0;
                sd_cmdOutState <= 0;
                sd_cmdOutDone <= 1;
                sd_respState <= 1;
            end
        end
        endcase
    end
    
    
    
    
    
    
    // ====================
    // Control State Machine
    // ====================
    
    reg ctrl_sdCmdOutDone=0, ctrl_sdCmdOutDoneTmp=0;
    always @(posedge ctrl_clk)
        {ctrl_sdCmdOutDone, ctrl_sdCmdOutDoneTmp} <= {ctrl_sdCmdOutDoneTmp, sd_cmdOutDone};
    
    reg ctrl_sdRespReady=0, ctrl_sdRespReadyTmp=0;
    always @(posedge ctrl_clk)
        {ctrl_sdRespReady, ctrl_sdRespReadyTmp} <= {ctrl_sdRespReadyTmp, sd_respReady};
    
    localparam Msg_StartBit = 1'b0;
    localparam Msg_EndBit   = 1'b1;
    
    localparam MsgCmd_Echo              = 8'h00;
    localparam MsgCmd_SDSetClkSrc       = 8'h01;
    localparam MsgCmd_SDSendCmd         = 8'h02;
    localparam MsgCmd_SDGetStatus       = 8'h03;
    localparam MsgCmd_SDDatOut          = 8'h04;
    
    reg[1:0] ctrl_state = 0;
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
                $display("[CTRL] Set SD clock source: %0d", ctrl_msgArg[1:0]);
                ctrl_sdClkSlow <= ctrl_msgArg[0];
                ctrl_sdClkFast <= ctrl_msgArg[1];
            end
            
            // Clock out SD command
            MsgCmd_SDSendCmd: begin
                $display("[CTRL] Clock out SD command to SD card: %0d", ctrl_dinReg);
                ctrl_sdCmdOutTrigger <= !ctrl_sdCmdOutTrigger;
            end
            
            // Get SD status / response
            MsgCmd_SDGetStatus: begin
                // $display("[CTRL] Clock out SD response to master: %0d", ctrl_dinReg);
                // We don't need synchronizers for sd_respCRCOK / sd_resp, because
                // they're guarded by `ctrl_sdRespReady`, which is synchronized.
                // Ie, sd_respCRCOK and sd_resp should be ignored unless ctrl_sdRespReady=1.
                // TODO: add a synchronizer for `sd_datIn`
                ctrl_doutReg <= {Msg_StartBit, 9'b0, sd_datIn, ctrl_sdCmdOutDone, ctrl_sdRespReady, sd_respCRCOK, sd_resp, Msg_EndBit};
            end
            
            MsgCmd_SDDatOut: begin
                ctrl_sdDatOutTrigger <= !ctrl_sdDatOutTrigger;
            end
            endcase
            
            ctrl_state <= 0;
        end
        endcase
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
        `finish;
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
    localparam CMD41    = 6'd41;    // SD_SEND_BIT_OP_COND
    localparam CMD55    = 6'd55;    // APP_CMD
    
    reg[65:0] ctrl_diReg;
    reg[65:0] ctrl_doReg;
    wire[63:0] ctrl_doReg_payload = ctrl_doReg[64:1];
    
    always @(posedge ctrl_clk) begin
        ctrl_diReg <= ctrl_diReg<<1|1'b1;
        ctrl_doReg <= ctrl_doReg<<1|ctrl_do;
    end
    
    assign ctrl_di = ctrl_diReg[65];
    
    initial begin
        reg[15:0] i, ii;
        reg sdDone;
        ctrl_diReg = ~0;
        
        wait(ctrl_clk);
        wait(!ctrl_clk);
        
        // Set SD clock source = 400 kHz
        ctrl_diReg = {START_BIT, 8'd1, 56'b01, END_BIT};
        for (i=0; i<66; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        for (i=0; i<128; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end

        // Send SD CMD0
        ctrl_diReg = {START_BIT, 8'd2, 8'b0, {2'b01, CMD0, 32'h00000000, 7'b0, 1'b1}, END_BIT};
        for (i=0; i<66; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end

        for (i=0; i<128; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end

        // Wait for SD command to be sent
        sdDone = 0;
        while (!sdDone) begin
            ctrl_diReg = {START_BIT, 8'd3, 56'b0, END_BIT};
            for (i=0; i<66; i++) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

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

            $display("Got respone: %b (SD command sent: %b, SD did resp: %b, CRC OK: %b, SD resp: %b)", ctrl_doReg, ctrl_doReg_payload[50], ctrl_doReg_payload[49], ctrl_doReg_payload[48], ctrl_doReg_payload[47:0]);
            sdDone = ctrl_doReg_payload[50];
        end

        // Send SD CMD8
        ctrl_diReg = {START_BIT, 8'd2, 8'b0, {2'b01, CMD8, 32'h000001AA, 7'b0, 1'b1}, END_BIT};
        for (i=0; i<66; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end

        for (i=0; i<128; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end

        // Get SD card response
        sdDone = 0;
        while (!sdDone) begin
            ctrl_diReg = {START_BIT, 8'd3, 56'b0, END_BIT};
            for (i=0; i<66; i++) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

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

            $display("Got respone: %b (SD command sent: %b, SD did resp: %b, CRC OK: %b, SD resp: %b)", ctrl_doReg, ctrl_doReg_payload[50], ctrl_doReg_payload[49], ctrl_doReg_payload[48], ctrl_doReg_payload[47:0]);
            sdDone = ctrl_doReg_payload[49];
        end
        
        
        
        
        
        
        
        
        // Start clocking out data on DAT lines
        ctrl_diReg = {START_BIT, 8'd4, 56'b0, END_BIT};
        for (i=0; i<66; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end

        for (i=0; i<128; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
    end
endmodule
`endif
