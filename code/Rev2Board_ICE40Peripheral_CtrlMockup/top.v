`include "../Util.v"
`include "../ClockGen.v"
`include "../MsgChannel.v"
`include "../CRC7.v"
`include "../CRC16.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`endif

`ifdef SIM
`include "../SDCardSim.v"
`endif

`timescale 1ns/1ps



// SyncPulse
//   Transmits a pulse signal across clock domains.
//   Pulses are dropped if they're sent faster than they can be consumed.
module SyncPulse(
    input wire              in_clk,
    input wire              in_trigger,
    input wire              out_clk,
    output wire             out_trigger
);
    reg in_req = 0;
    reg in_ack = 0;
    wire in_idle = !in_req & !in_ack;
    always @(posedge in_clk)
        if (in_idle & in_trigger) begin
            in_req <= 1;

        end else if (in_ack)
            in_req <= 0;

    reg out_req=0, out_req2=0;
    reg tmp1 = 0;
    always @(posedge out_clk)
        { out_req2, out_req, tmp1 } <= { out_req, tmp1, in_req };

    reg tmp2 = 0;
    always @(posedge in_clk)
        { in_ack, tmp2 } <= { tmp2, out_req };

    assign out_trigger = !out_req2 & out_req; // Trigger pulse occurs upon the positive edge of `out_req`.
endmodule


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
    // Fast Clock (180 MHz)
    // ====================
    wire fastClk;
    ClockGen #(
        .FREQ(180000000),
        .DIVR(0),
        .DIVF(59),
        .DIVQ(2),
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
        .PIN_TYPE(6'b0000_00)
    ) SB_IO_ctrl_clk (
        .INPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_di),
        .D_IN_0(ctrlDI)
    );
    
    
    
    // ====================
    // Pin: ctrl_do
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_01)
    ) SB_IO_ctrl_do (
        .OUTPUT_CLK(ctrl_clk),
        .PACKAGE_PIN(ctrl_do),
        .OUTPUT_ENABLE(1'b1),
        .D_OUT_0(ctrl_doutReg[64])
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
    // Registers
    // ====================
    reg[47:0] sd_shiftReg = 0;
    reg[2:0] sd_cmdOutActive = 0;
    wire[6:0] sd_cmdOutCRC;
    reg sd_cmdOutCRCRst_ = 0;
    wire[6:0] sd_respCRC;
    reg[6:0] sd_respExpectedCRC = 0;
    reg sd_respCRCRst_ = 0;
    
    wire sd_cmdIn;
    reg[47:0] sd_resp = 0;
    reg sd_cmdOutDone = 0;
    reg sd_respReady = 0;
    reg sd_respCRCOK = 0;
    
    reg[5:0] sd_counter = 0;
    
    reg ctrl_dinActive = 0;
    reg[63:0] ctrl_dinReg = 0;
    wire[3:0] ctrl_cmdCmd = ctrl_dinReg[63:60];
    wire[59:0] ctrl_cmdArg = ctrl_dinReg[59:0];
    
    reg[64:0] ctrl_doutReg = 0;
    
    reg[6:0] ctrl_counter = 0;
    reg ctrl_sdClkSlow = 0;
    reg ctrl_sdClkFast = 0;
    
    reg ctrl_cmdOutTrigger = 0;
    
    
    
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
    
    // ====================
    // SD State Machine
    // ====================
    
    reg[2:0] sd_cmdOutTriggerTmp = 0;
    wire sd_cmdOutTrigger = sd_cmdOutTriggerTmp[2]!==sd_cmdOutTriggerTmp[1];
    always @(posedge sd_clk)
        sd_cmdOutTriggerTmp <= (sd_cmdOutTriggerTmp<<1)|ctrl_cmdOutTrigger;
    
    reg[1:0] sd_cmdOutState = 0;
    reg[1:0] sd_respState = 0;
    always @(posedge sd_clk) begin
        sd_shiftReg <= (sd_shiftReg<<1)|(sd_cmdOutActive[2] ? 1'b1 : sd_cmdIn);
        sd_counter <= sd_counter-1;
        sd_cmdOutActive <= (sd_cmdOutActive<<1)|sd_cmdOutActive[0];
        sd_respExpectedCRC <= sd_respExpectedCRC<<1;
        
        case (sd_respState)
        0: begin
        end
        
        1: begin
            sd_respCRCRst_ <= 0;
            sd_respCRCOK <= 1;
            if (!sd_cmdIn) begin
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
                $display("[CTRL] Response: Good CRC bit ✅");
            end else begin
                sd_respCRCOK <= 0;
                $display("[CTRL] Response: bad CRC bit (wanted: %b, got: %b) ❌", sd_respExpectedCRC[6], sd_shiftReg[1]);
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
                sd_shiftReg <= ctrl_dinReg;
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
    
    reg ctrl_sdRespReady=0, ctrl_sdRespReadyTmp=0;
    always @(posedge ctrl_clk)
        {ctrl_sdRespReady, ctrl_sdRespReadyTmp} <= {ctrl_sdRespReadyTmp, sd_respReady};
    
    reg ctrl_sdCmdOutDone=0, ctrl_sdCmdOutDoneTmp=0;
    always @(posedge ctrl_clk)
        {ctrl_sdCmdOutDone, ctrl_sdCmdOutDoneTmp} <= {ctrl_sdCmdOutDoneTmp, sd_cmdOutDone};
    
    reg[1:0] ctrl_state = 0;
    always @(posedge ctrl_clk) begin
        if (ctrl_dinActive) ctrl_dinReg <= (ctrl_dinReg<<1)|ctrlDI;
        ctrl_counter <= ctrl_counter-1;
        ctrl_doutReg <= ctrl_doutReg<<1|1'b1;
        
        case (ctrl_state)
        0: begin
            ctrl_counter <= 63;
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
            $display("[CTRL] Got command: %b [cmd: %0d, arg: %0d]", ctrl_dinReg, ctrl_cmdCmd, ctrl_cmdArg);
            case (ctrl_cmdCmd)
            // Set SD clock source
            0: begin
                $display("[CTRL] Set SD clock source: %0d", ctrl_cmdArg[1:0]);
                ctrl_sdClkSlow <= ctrl_cmdArg[0];
                ctrl_sdClkFast <= ctrl_cmdArg[1];
            end
            
            // Clock out SD command
            1: begin
                $display("[CTRL] Clock out SD command to SD card: %0d", ctrl_dinReg);
                ctrl_cmdOutTrigger <= !ctrl_cmdOutTrigger;
            end
            
            // Get SD status / response
            2: begin
                $display("[CTRL] Clock out SD response to master: %0d", ctrl_dinReg);
                ctrl_doutReg <= {1'b0, 13'b0, sd_cmdOutDone, ctrl_sdRespReady, sd_respCRCOK, sd_resp};
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
    wire        ctrl_di;
    wire        ctrl_do;
    
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
    
    localparam CMD0 =   6'd0;      // GO_IDLE_STATE
    localparam CMD2 =   6'd2;      // ALL_SEND_CID
    localparam CMD3 =   6'd3;      // SEND_RELATIVE_ADDR
    localparam CMD6 =   6'd6;      // SWITCH_FUNC
    localparam CMD7 =   6'd7;      // SELECT_CARD/DESELECT_CARD
    localparam CMD8 =   6'd8;      // SEND_IF_COND
    localparam CMD11 =  6'd11;     // VOLTAGE_SWITCH
    localparam CMD41 =  6'd41;     // SD_SEND_OP_COND
    localparam CMD55 =  6'd55;     // APP_CMD
    
    reg[64:0] ctrl_diReg;
    reg[64:0] ctrl_doReg;
    always @(posedge ctrl_clk) begin
        ctrl_diReg <= ctrl_diReg<<1|1'b1;
        ctrl_doReg <= ctrl_doReg<<1|ctrl_do;
    end
    
    assign ctrl_di = ctrl_diReg[64];
    
    initial begin
        reg[15:0] i, ii;
        reg sdDone;
        ctrl_diReg = ~0;
        
        wait(ctrl_clk);
        wait(!ctrl_clk);
        
        // Set SD clock source = 400 kHz
        ctrl_diReg = {1'b0, 4'd0, 60'b01};
        for (i=0; i<65; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        for (i=0; i<128; i++) begin
            wait(ctrl_clk);
            wait(!ctrl_clk);
        end
        
        // Send SD CMD0
        ctrl_diReg = {1'b0, 4'd1, 12'b0, {2'b01, CMD0, 32'h00000000, 7'b0, 1'b1}};
        for (i=0; i<65; i++) begin
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
            ctrl_diReg = {1'b0, 4'd2, 60'b0};
            for (i=0; i<65; i++) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

            // Wait for response to start
            while (ctrl_doReg[0]) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

            // Load the full response
            for (i=0; i<64; i++) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

            $display("Got respone: %b (SD command sent: %b, SD did resp: %b, CRC OK: %b, SD resp: %b)", ctrl_doReg, ctrl_doReg[50], ctrl_doReg[49], ctrl_doReg[48], ctrl_doReg[47:0]);
            sdDone = ctrl_doReg[50];
        end

        // Send SD CMD8
        ctrl_diReg = {1'b0, 4'd1, 12'b0, {2'b01, CMD8, 32'h000001AA, 7'b0, 1'b1}};
        for (i=0; i<65; i++) begin
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
            ctrl_diReg = {1'b0, 4'd2, 60'b0};
            for (i=0; i<65; i++) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

            // Wait for response to start
            while (ctrl_doReg[0]) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

            // Load the full response
            for (i=0; i<64; i++) begin
                wait(ctrl_clk);
                wait(!ctrl_clk);
            end

            $display("Got respone: %b (SD command sent: %b, SD did resp: %b, CRC OK: %b, SD resp: %b)", ctrl_doReg, ctrl_doReg[50], ctrl_doReg[49], ctrl_doReg[48], ctrl_doReg[47:0]);
            sdDone = ctrl_doReg[49];
        end
    end
endmodule
`endif
