`include "Sync.v"
`include "TogglePulse.v"
`include "ToggleAck.v"
`include "ClockGen.v"
`include "SDController.v"

`ifdef SIM
`include "SDCardSim.v"
`endif

`timescale 1ns/1ps

// ====================
// Control Messages/Responses
// ====================
`define Msg_Len                                         64

`define Msg_Type_Len                                    8
`define Msg_Type_Bits                                   63:56

`define Msg_Arg_Len                                     56
`define Msg_Arg_Bits                                    55:0

`define Resp_Len                                        `Msg_Len
`define Resp_Arg_Bits                                   63:0

`define Msg_Type_Echo                                   `Msg_Type_Len'h00
`define     Msg_Arg_Echo_Msg_Len                        56
`define     Msg_Arg_Echo_Msg_Bits                       55:0
`define     Resp_Arg_Echo_Msg_Bits                      63:8

`define Msg_Type_SDClkSrc                               `Msg_Type_Len'h01
`define     Msg_Arg_SDClkSrc_Delay_Bits                 5:2
`define     Msg_Arg_SDClkSrc_Speed_Len                  2
`define     Msg_Arg_SDClkSrc_Speed_Bits                 1:0
`define     Msg_Arg_SDClkSrc_Speed_Off                  `Msg_Arg_SDClkSrc_Speed_Len'b00
`define     Msg_Arg_SDClkSrc_Speed_Slow                 `Msg_Arg_SDClkSrc_Speed_Len'b01
`define     Msg_Arg_SDClkSrc_Speed_Slow_Bits            0:0
`define     Msg_Arg_SDClkSrc_Speed_Fast                 `Msg_Arg_SDClkSrc_Speed_Len'b10
`define     Msg_Arg_SDClkSrc_Speed_Fast_Bits            1:1

`define Msg_Type_SDSendCmd                              `Msg_Type_Len'h02
`define     Msg_Arg_SDRespType_Len                      2
`define     Msg_Arg_SDRespType_Bits                     49:48
`define     Msg_Arg_SDRespType_None                     `Msg_Arg_SDRespType_Len'b00
`define     Msg_Arg_SDRespType_48                       `Msg_Arg_SDRespType_Len'b01
`define     Msg_Arg_SDRespType_48_Bits                  48:48
`define     Msg_Arg_SDRespType_136                      `Msg_Arg_SDRespType_Len'b10
`define     Msg_Arg_SDRespType_136_Bits                 49:49
`define     Msg_Arg_SDDatInType_Len                     1
`define     Msg_Arg_SDDatInType_Bits                    50:50
`define     Msg_Arg_SDDatInType_None                    `Msg_Arg_SDDatInType_Len'b0
`define     Msg_Arg_SDDatInType_512                     `Msg_Arg_SDDatInType_Len'b1
`define     Msg_Arg_SDDatInType_512_Bits                50:50
`define     Msg_Arg_SDCmd_Bits                          47:0

`define Msg_Type_SDDatOut                               `Msg_Type_Len'h03

`define Msg_Type_SDGetStatus                            `Msg_Type_Len'h04
`define     Resp_Arg_SDCmdDone_Bits                     63:63
`define     Resp_Arg_SDRespDone_Bits                    62:62
`define         Resp_Arg_SDRespCRCErr_Bits              61:61
`define         Resp_Arg_SDResp_Bits                    60:13
`define         Resp_Arg_SDResp_Len                     48
`define     Resp_Arg_SDDatOutDone_Bits                  12:12
`define         Resp_Arg_SDDatOutCRCErr_Bits            11:11
`define     Resp_Arg_SDDatInDone_Bits                   10:10
`define         Resp_Arg_SDDatInCRCErr_Bits             9:9
`define         Resp_Arg_SDDatInCMD6AccessMode_Bits     8:5
`define     Resp_Arg_SDDat0Idle_Bits                    4:4
`define     Resp_Arg_SDFiller_Bits                      3:0

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
    // Clock (120 MHz)
    // ====================
    localparam ClkFreq = 120_000_000;
    wire clk;
    ClockGen #(
        .FREQ(ClkFreq),
        .DIVR(0),
        .DIVF(39),
        .DIVQ(3),
        .FILTER_RANGE(2)
    ) ClockGen(.clkRef(clk24mhz), .clk(clk));
    
    
    
    
    
    
    // ====================
    // SDController
    // ====================
    reg[1:0]    sd_clksrc_speed = 0;
    reg[3:0]    sd_clksrc_delay = 0;
    reg         sd_cmd_trigger = 0;
    reg[47:0]   sd_cmd_data = 0;
    reg[1:0]    sd_cmd_respType = 0;
    reg         sd_cmd_datInType = 0;
    wire        sd_cmd_done;
    wire        sd_resp_done;
    wire[47:0]  sd_resp_data;
    wire        sd_resp_crcErr;
    reg         sd_datOut_start = 0;
    wire        sd_datOut_ready;
    wire        sd_datOut_done;
    wire        sd_datOut_crcErr;
    wire        sd_datOutWrite_clk;
    wire        sd_datOutWrite_ready;
    reg         sd_datOutWrite_trigger = 0;
    reg[15:0]   sd_datOutWrite_data = 0;
    wire        sd_datIn_done;
    wire        sd_datIn_crcErr;
    wire[3:0]   sd_datIn_cmd6AccessMode;
    wire        sd_status_dat0Idle;
    
    SDController #(
        .ClkFreq(ClkFreq)
    ) SDController (
        .clk(clk),
        
        .sdcard_clk(sd_clk),
        .sdcard_cmd(sd_cmd),
        .sdcard_dat(sd_dat),
        
        .clksrc_speed(sd_clksrc_speed),
        .clksrc_delay(sd_clksrc_delay),
        
        .cmd_trigger(sd_cmd_trigger),
        .cmd_data(sd_cmd_data),
        .cmd_respType(sd_cmd_respType),
        .cmd_datInType(sd_cmd_datInType),
        .cmd_done(sd_cmd_done),
        
        .resp_done(sd_resp_done),
        .resp_data(sd_resp_data),
        .resp_crcErr(sd_resp_crcErr),
        
        .datOut_start(sd_datOut_start),
        .datOut_ready(sd_datOut_ready),
        .datOut_done(sd_datOut_done),
        .datOut_crcErr(sd_datOut_crcErr),
        
        .datOutWrite_clk(sd_datOutWrite_clk),
        .datOutWrite_ready(sd_datOutWrite_ready),
        .datOutWrite_trigger(sd_datOutWrite_trigger),
        .datOutWrite_data(sd_datOutWrite_data),
        
        .datIn_done(sd_datIn_done),
        .datIn_crcErr(sd_datIn_crcErr),
        .datIn_cmd6AccessMode(sd_datIn_cmd6AccessMode),
        
        .status_dat0Idle(sd_status_dat0Idle)
    );
    
    
    
    
    
    
    // ====================
    // sd_datOutWrite_clk
    // ====================
    reg clkDivider = 0;
    always @(posedge clk) clkDivider <= clkDivider+1;
    assign sd_datOutWrite_clk = clkDivider;
    
    
    // ====================
    // DatOut Writer State Machine
    // ====================
    // reg sdDatOut_writeTrigger = 0;
    // `TogglePulse(sdDatOut_ready, sd_datOut_ready, posedge, clk);
    // reg[1:0] sdDatOut_state = 0;
    // always @(posedge clk) begin
    //     case (sdDatOut_state)
    //     0: begin
    //         if (sdDatOut_trigger) begin
    //             // Start SDController DatOut
    //             sd_datOut_start <= !sd_datOut_start;
    //             sdDatOut_state <= 1;
    //         end
    //     end
    //
    //     1: begin
    //         // Wait for SDController DatOut to be ready
    //         if (sdDatOut_ready) begin
    //             sdDatOut_writeTrigger <= !sdDatOut_writeTrigger;
    //             sdDatOut_state <= 0;
    //         end
    //     end
    //     endcase
    // end
    
    reg ctrl_sdDatOutTrigger = 0;
    `TogglePulse(w_sdDatOutTrigger, ctrl_sdDatOutTrigger, posedge, sd_datOutWrite_clk);
    `TogglePulse(w_sdDatOutReady, sd_datOut_ready, posedge, sd_datOutWrite_clk);
    reg[1:0] w_state = 0;
    reg[22:0] w_counter = 0;
    always @(posedge sd_datOutWrite_clk) begin
        sd_datOutWrite_trigger <= 0;
        
        case (w_state)
        0: begin
        end
        
        1: begin
            // Start SDController DatOut
            sd_datOut_start <= !sd_datOut_start;
            w_state <= 2;
        end
        
        2: begin
            sd_datOutWrite_data <= 0;
            // sd_datOutWrite_data <= 16'hFFFF;
            w_counter <= 0;
            
            // Wait for SDController DatOut to be ready
            if (w_sdDatOutReady) begin
                w_state <= 3;
            end
        end
        
        3: begin
            sd_datOutWrite_trigger <= 1;
            if (sd_datOutWrite_ready && sd_datOutWrite_trigger) begin
                w_counter <= w_counter+1;
                sd_datOutWrite_data <= sd_datOutWrite_data+1;
            end
`ifdef SIM
            if (w_counter === 'hA00-2) begin
`else
            if (w_counter === (2304*1296)-2) begin
`endif
            // if (w_counter === 'hFE) begin
                $display("[CTRL] Finished writing into FIFO");
                w_state <= 0;
            end
        end
        endcase
        
        if (w_sdDatOutTrigger) begin
            w_state <= 1;
        end
    end
    
    
    
    
    
    
    
    
    // ====================
    // Control State Machine
    // ====================
    reg[1:0] ctrl_state = 0;
    reg[6:0] ctrl_counter = 0;
    // +5 for delay states, so that clients send an extra byte before receiving the response
    reg[`Resp_Len+5-1:0] ctrl_doutReg = 0;
    
    wire ctrl_rst_;
    wire ctrl_din;
    reg[`Msg_Len-1:0] ctrl_dinReg = 0;
    wire[`Msg_Type_Len-1:0] ctrl_msgType = ctrl_dinReg[`Msg_Type_Bits];
    wire[`Msg_Arg_Len-1:0] ctrl_msgArg = ctrl_dinReg[`Msg_Arg_Bits];
    
    `ToggleAck(ctrl_sdCmdDone_, ctrl_sdCmdDoneAck, sd_cmd_done, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdRespDone_, ctrl_sdRespDoneAck, sd_resp_done, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatOutDone_, ctrl_sdDatOutDoneAck, sd_datOut_done, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatInDone_, ctrl_sdDatInDoneAck, sd_datIn_done, posedge, ctrl_clk);
    
    `Sync(ctrl_sdDat0Idle, sd_status_dat0Idle, posedge, ctrl_clk);
    
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
                    $display("[CTRL] Got Msg_Type_Echo: %0h", ctrl_msgArg[`Msg_Arg_Echo_Msg_Bits]);
                    ctrl_doutReg[`Resp_Arg_Echo_Msg_Bits] <= ctrl_msgArg[`Msg_Arg_Echo_Msg_Bits];
                end
                
                // Set SD clock source
                `Msg_Type_SDClkSrc: begin
                    $display("[CTRL] Got Msg_Type_SDClkSrc: delay=%0d fast=%b slow=%b",
                        ctrl_msgArg[`Msg_Arg_SDClkSrc_Delay_Bits],
                        ctrl_msgArg[`Msg_Arg_SDClkSrc_Speed_Fast_Bits],
                        ctrl_msgArg[`Msg_Arg_SDClkSrc_Speed_Slow_Bits]);
                    
                    // We don't need to synchronize `sd_ctrl_clkDelay` into the sd_ domain,
                    // because it should only be set while the sd_ clock is disabled.
                    sd_clksrc_delay <= ctrl_msgArg[`Msg_Arg_SDClkSrc_Delay_Bits];
                    
                    case (ctrl_msgArg[`Msg_Arg_SDClkSrc_Speed_Bits])
                    `Msg_Arg_SDClkSrc_Speed_Off:    sd_clksrc_speed <= SDController.ClkSrc_Speed_Off;
                    `Msg_Arg_SDClkSrc_Speed_Slow:   sd_clksrc_speed <= SDController.ClkSrc_Speed_Slow;
                    `Msg_Arg_SDClkSrc_Speed_Fast:   sd_clksrc_speed <= SDController.ClkSrc_Speed_Fast;
                    endcase
                end
                
                // Clock out SD command
                `Msg_Type_SDSendCmd: begin
                    $display("[CTRL] Got Msg_Type_SDSendCmd [respType:%0b]", ctrl_msgArg[`Msg_Arg_SDRespType_Bits]);
                    // Reset ctrl_sdCmdDone_ / ctrl_sdRespDone_ / ctrl_sdDatInDone_
                    if (!ctrl_sdCmdDone_) ctrl_sdCmdDoneAck <= !ctrl_sdCmdDoneAck;
                    
                    if (!ctrl_sdRespDone_ && ctrl_msgArg[`Msg_Arg_SDRespType_Bits]!==`Msg_Arg_SDRespType_None)
                        ctrl_sdRespDoneAck <= !ctrl_sdRespDoneAck;
                    
                    if (!ctrl_sdDatInDone_ && ctrl_msgArg[`Msg_Arg_SDDatInType_Bits]!==`Msg_Arg_SDDatInType_None)
                        ctrl_sdDatInDoneAck <= !ctrl_sdDatInDoneAck;
                    
                    case (ctrl_msgArg[`Msg_Arg_SDRespType_Bits])
                    `Msg_Arg_SDRespType_None:   sd_cmd_respType <= SDController.RespType_None;
                    `Msg_Arg_SDRespType_48:     sd_cmd_respType <= SDController.RespType_48;
                    `Msg_Arg_SDRespType_136:    sd_cmd_respType <= SDController.RespType_136;
                    endcase
                    
                    case (ctrl_msgArg[`Msg_Arg_SDDatInType_Bits])
                    `Msg_Arg_SDDatInType_None:  sd_cmd_datInType <= SDController.DatInType_None;
                    `Msg_Arg_SDDatInType_512:   sd_cmd_datInType <= SDController.DatInType_512;
                    endcase
                    
                    sd_cmd_data <= ctrl_msgArg[`Msg_Arg_SDCmd_Bits];
                    sd_cmd_trigger <= !sd_cmd_trigger;
                end
                
                `Msg_Type_SDDatOut: begin
                    $display("[CTRL] Got Msg_Type_SDDatOut");
                    if (!ctrl_sdDatOutDone_) ctrl_sdDatOutDoneAck <= !ctrl_sdDatOutDoneAck;
                    ctrl_sdDatOutTrigger <= !ctrl_sdDatOutTrigger;
                end
                
                // Get SD status / response
                `Msg_Type_SDGetStatus: begin
                    $display("[CTRL] Got Msg_Type_SDGetStatus");
                    
                    ctrl_doutReg[`Resp_Arg_SDCmdDone_Bits] <= !ctrl_sdCmdDone_;
                    ctrl_doutReg[`Resp_Arg_SDRespDone_Bits] <= !ctrl_sdRespDone_;
                        ctrl_doutReg[`Resp_Arg_SDRespCRCErr_Bits] <= sd_resp_crcErr;
                    ctrl_doutReg[`Resp_Arg_SDDatOutDone_Bits] <= !ctrl_sdDatOutDone_;
                        ctrl_doutReg[`Resp_Arg_SDDatOutCRCErr_Bits] <= sd_datOut_crcErr;
                    ctrl_doutReg[`Resp_Arg_SDDatInDone_Bits] <= !ctrl_sdDatInDone_;
                        ctrl_doutReg[`Resp_Arg_SDDatInCRCErr_Bits] <= sd_datIn_crcErr;
                        ctrl_doutReg[`Resp_Arg_SDDatInCMD6AccessMode_Bits] <= sd_datIn_cmd6AccessMode;
                    ctrl_doutReg[`Resp_Arg_SDDat0Idle_Bits] <= ctrl_sdDat0Idle;
                    ctrl_doutReg[`Resp_Arg_SDResp_Bits] <= sd_resp_data;
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
endmodule







`ifdef SIM
module Testbench();
    reg         clk24mhz;
    
    reg         ctrl_clk;
    reg         ctrl_rst;
    tri1        ctrl_di;
    tri1        ctrl_do;
    
    wire        sd_clk;
    wire        sd_cmd;
    wire[3:0]   sd_dat;
    wire[3:0]   led;
    
    Top Top(.*);
    
    SDCardSim SDCardSim(
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat)
    );
    
    initial begin
        $dumpfile("Top.vcd");
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
    localparam CMD12    = 6'd12;    // STOP_TRANSMISSION
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
        arg[`Msg_Arg_SDRespType_Bits] = respType;
        arg[`Msg_Arg_SDDatInType_Bits] = datInType;
        arg[`Msg_Arg_SDCmd_Bits] = {2'b01, sdCmd, sdArg, 7'b0, 1'b1};
        
        SendMsg(`Msg_Type_SDSendCmd, arg);
    end endtask
    
    task SendSDCmdResp(input[5:0] sdCmd, input[`Msg_Arg_SDRespType_Len-1:0] respType, input[`Msg_Arg_SDDatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg[15:0] i;
        reg done;
        SendSDCmd(sdCmd, respType, datInType, sdArg);
        
        // Wait for SD command to be sent
        done = 0;
        for (i=0; i<1000 && !done; i++) begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            
            // If a response is expected, we're done when the response is received
            if (respType !== `Msg_Arg_SDRespType_None) done = resp[`Resp_Arg_SDRespDone_Bits];
            // If a response isn't expected, we're done when the command is sent
            else done = resp[`Resp_Arg_SDCmdDone_Bits];
        end
        
        if (!done) begin
            $display("[EXT] SD card response timeout ❌");
            `Finish;
        end
        
    end endtask
    
    task TestNoOp; begin
        // ====================
        // Test NoOp command
        // ====================

        SendMsgResp(`Msg_Type_NoOp, 56'h66554433221100);
        if (resp === 64'hFFFFFFFFFFFFFFFF) begin
            $display("Response OK ✅: %h", resp);
        end else begin
            $display("Bad response ❌: %h", resp);
            `Finish;
        end
    end endtask
    
    task TestEcho; begin
        // ====================
        // Test Echo command
        // ====================
        reg[`Msg_Arg_Echo_Msg_Len-1:0] arg;
        arg = `Msg_Arg_Echo_Msg_Len'h66554433221100;
        
        SendMsgResp(`Msg_Type_Echo, arg);
        if (resp[`Resp_Arg_Echo_Msg_Bits] === arg) begin
            $display("Response OK ✅: %h", resp);
        end else begin
            $display("Bad response ❌: %h", resp);
            `Finish;
        end
    end endtask
    
    task TestSDCMD0; begin
        SendSDCmdResp(CMD0, `Msg_Arg_SDRespType_None, `Msg_Arg_SDDatInType_None, 0);
    end endtask
    
    task TestSDCMD8; begin
        // ====================
        // Test SD CMD8 (SEND_IF_COND)
        // ====================
        reg[`Resp_Arg_SDResp_Len-1:0] sdResp;
        
        // Send SD CMD8
        SendSDCmdResp(CMD8, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 32'h000001AA);
        if (resp[`Resp_Arg_SDRespCRCErr_Bits] !== 1'b0) begin
            $display("[EXT] CRC error ❌");
            `Finish;
        end

        sdResp = resp[`Resp_Arg_SDResp_Bits];
        if (sdResp[15:8] !== 8'hAA) begin
            $display("[EXT] Bad response: %h ❌", resp);
            `Finish;
        end
    end endtask
    
    task TestSDDatOut; begin
        // ====================
        // Test writing data to SD card / DatOut
        // ====================
        
        // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        SendSDCmdResp(CMD55, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 32'b0);
        SendSDCmdResp(ACMD23, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 32'b1);
        
        // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        SendSDCmdResp(CMD25, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 32'b0);
        
        // Clock out data on DAT lines
        SendMsg(`Msg_Type_SDDatOut, 0);
        
        // Wait until we're done clocking out data on DAT lines
        $display("[EXT] Waiting while data is written...");
        do begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
        end while(!resp[`Resp_Arg_SDDatOutDone_Bits]);
        $display("[EXT] Done writing (SD resp: %b)", resp[`Resp_Arg_SDResp_Bits]);
        
        // Check CRC status
        if (resp[`Resp_Arg_SDDatOutCRCErr_Bits] === 1'b0) begin
            $display("[EXT] DatOut CRC OK ✅");
        end else begin
            $display("[EXT] DatOut CRC bad ❌");
            `Finish;
        end
        
        // Stop transmission
        SendSDCmdResp(CMD12, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 32'b0);
    end endtask
    
    task TestSDDatIn; begin
        // ====================
        // Test CMD6 (SWITCH_FUNC) + DatIn
        // ====================
        
        // Send SD command CMD6 (SWITCH_FUNC)
        SendSDCmdResp(CMD6, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_512, 32'h80FFFFF3);
        $display("[EXT] Waiting for DatIn to complete...");
        do begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
        end while(!resp[`Resp_Arg_SDDatInDone_Bits]);
        $display("[EXT] DatIn completed");

        // Check DatIn CRC status
        if (resp[`Resp_Arg_SDDatInCRCErr_Bits] === 1'b0) begin
            $display("[EXT] DatIn CRC OK ✅");
        end else begin
            $display("[EXT] DatIn CRC bad ❌");
            `Finish;
        end

        // Check the access mode from the CMD6 response
        if (resp[`Resp_Arg_SDDatInCMD6AccessMode_Bits] === 4'h3) begin
            $display("[EXT] CMD6 access mode == 0x3 ✅");
        end else begin
            $display("[EXT] CMD6 access mode == 0x%h ❌", resp[`Resp_Arg_SDDatInCMD6AccessMode_Bits]);
            `Finish;
        end
    end endtask
    
    
    task TestSDCMD2; begin
        // ====================
        // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
        //   Note: we expect CRC errors in the response because the R2
        //   response CRC doesn't follow the semantics of other responses
        // ====================
        
        // Send SD command CMD2 (ALL_SEND_CID)
        SendSDCmdResp(CMD2, `Msg_Arg_SDRespType_136, `Msg_Arg_SDDatInType_None, 0);
        $display("====================================================");
        $display("^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        $display("====================================================");
    end endtask
    
    task TestSDRespRecovery; begin
        reg done;
        reg[15:0] i;
        
        // Send an SD command that doesn't provide a response
        SendSDCmd(CMD0, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 0);
        $display("[EXT] Verifying that Resp times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            $display("[EXT] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                resp[`Resp_Arg_SDCmdDone_Bits],
                resp[`Resp_Arg_SDRespDone_Bits],
                resp[`Resp_Arg_SDDatOutDone_Bits],
                resp[`Resp_Arg_SDDatInDone_Bits]);

            done = resp[`Resp_Arg_SDRespDone_Bits];
        end
        
        if (!done) begin
            $display("[EXT] Resp timeout ✅");
            $display("[EXT] Testing Resp after timeout...");
            TestSDCMD8();
            $display("[EXT] Resp Recovered ✅");
        
        end else begin
            $display("[EXT] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
        
        
        
        
        
        
        
    task TestSDDatOutRecovery; begin
        reg done;
        reg[15:0] i;
        
        // // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        // SendSDCmdResp(CMD25, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 32'b0);
        
        // Send command SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        // SendSDCmd(CMD0, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_None, 0);
        
        // Clock out data on DAT lines
        SendMsg(`Msg_Type_SDDatOut, 0);
        
        #50000;
        
        // Verify that we timeout
        $display("[EXT] Verifying that DatOut times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            $display("[EXT] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                resp[`Resp_Arg_SDCmdDone_Bits],
                resp[`Resp_Arg_SDRespDone_Bits],
                resp[`Resp_Arg_SDDatOutDone_Bits],
                resp[`Resp_Arg_SDDatInDone_Bits]);

            done = resp[`Resp_Arg_SDDatOutDone_Bits];
        end

        if (!done) begin
            $display("[EXT] DatOut timeout ✅");
            $display("[EXT] Testing DatOut after timeout...");
            TestSDDatOut();
            $display("[EXT] DatOut Recovered ✅");

        end else begin
            $display("[EXT] DatOut didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    task TestSDDatInRecovery; begin
        reg done;
        reg[15:0] i;
        
        // Send SD command that doesn't respond on the DAT lines,
        // but specify that we expect DAT data
        SendSDCmdResp(CMD8, `Msg_Arg_SDRespType_48, `Msg_Arg_SDDatInType_512, 0);
        $display("[EXT] Verifying that DatIn times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            $display("[EXT] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                resp[`Resp_Arg_SDCmdDone_Bits],
                resp[`Resp_Arg_SDRespDone_Bits],
                resp[`Resp_Arg_SDDatOutDone_Bits],
                resp[`Resp_Arg_SDDatInDone_Bits]);
            
            done = resp[`Resp_Arg_SDDatInDone_Bits];
        end

        if (!done) begin
            $display("[EXT] DatIn timeout ✅");
            $display("[EXT] Testing DatIn after timeout...");
            TestSDDatIn();
            $display("[EXT] DatIn Recovered ✅");
        
        end else begin
            $display("[EXT] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        
        // Set our initial state
        ctrl_clk = 0;
        ctrl_rst = 1;
        ctrl_diReg = ~0;
        #1;
        
        
        // Disable SD clock
        SendMsg(`Msg_Type_SDClkSrc, `Msg_Arg_SDClkSrc_Speed_Off);

        // Set SD clock source
        SendMsg(`Msg_Type_SDClkSrc, `Msg_Arg_SDClkSrc_Speed_Fast);
        // SendMsg(`Msg_Type_SDClkSrc, `Msg_Arg_SDClkSrc_Speed_Slow);
        
        TestNoOp();
        TestEcho();
        
        forever begin
            i = $urandom%10;
            case (i)
            0: TestSDCMD0();
            1: TestSDCMD8();
            2: TestSDDatOut();
            3: TestSDDatOut();
            4: TestSDCMD2();
            5: TestSDCMD2();
            6: TestSDDatIn();
            7: TestSDRespRecovery();
            8: TestSDDatOutRecovery();
            9: TestSDDatInRecovery();
            endcase
        end
        
        `Finish;
        
    end
endmodule
`endif
