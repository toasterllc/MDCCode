`include "Sync.v"
`include "TogglePulse.v"
`include "ToggleAck.v"
`include "ClockGen.v"
`include "SDController.v"
`include "PixI2CMaster.v"

`ifdef SIM
`include "/usr/local/share/yosys/ice40/cells_sim.v"
`include "SDCardSim.v"
`endif

`timescale 1ns/1ps

// ====================
// Control Messages/Responses
// ====================
`define Msg_Len                                                 64

`define Msg_Type_Len                                            8
`define Msg_Type_Bits                                           63:56

`define Msg_Arg_Len                                             56
`define Msg_Arg_Bits                                            55:0

`define Resp_Len                                                `Msg_Len
`define Resp_Arg_Bits                                           63:0

`define Msg_Type_Echo                                           `Msg_Type_Len'h00

`define Msg_Type_SDClkSet                                       `Msg_Type_Len'h01
`define     Msg_Arg_SDClkSet_ClkDelay_Bits                      5:2
`define     Msg_Arg_SDClkSet_ClkSrc_Len                         2
`define     Msg_Arg_SDClkSet_ClkSrc_Bits                        1:0
`define     Msg_Arg_SDClkSet_ClkSrc_None                        `Msg_Arg_SDClkSet_ClkSrc_Len'b00
`define     Msg_Arg_SDClkSet_ClkSrc_Slow                        `Msg_Arg_SDClkSet_ClkSrc_Len'b01
`define     Msg_Arg_SDClkSet_ClkSrc_Slow_Bits                   0:0
`define     Msg_Arg_SDClkSet_ClkSrc_Fast                        `Msg_Arg_SDClkSet_ClkSrc_Len'b10
`define     Msg_Arg_SDClkSet_ClkSrc_Fast_Bits                   1:1

`define Msg_Type_SDSendCmd                                      `Msg_Type_Len'h02
`define     Msg_Arg_SDSendCmd_RespType_Len                      2
`define     Msg_Arg_SDSendCmd_RespType_Bits                     49:48
`define     Msg_Arg_SDSendCmd_RespType_0                        `Msg_Arg_SDSendCmd_RespType_Len'b00
`define     Msg_Arg_SDSendCmd_RespType_48                       `Msg_Arg_SDSendCmd_RespType_Len'b01
`define     Msg_Arg_SDSendCmd_RespType_48_Bits                  0:0
`define     Msg_Arg_SDSendCmd_RespType_136                      `Msg_Arg_SDSendCmd_RespType_Len'b10
`define     Msg_Arg_SDSendCmd_RespType_136_Bits                 1:1
`define     Msg_Arg_SDSendCmd_DatInType_Len                     1
`define     Msg_Arg_SDSendCmd_DatInType_Bits                    50:50
`define     Msg_Arg_SDSendCmd_DatInType_0                       `Msg_Arg_SDSendCmd_DatInType_Len'b0
`define     Msg_Arg_SDSendCmd_DatInType_512                     `Msg_Arg_SDSendCmd_DatInType_Len'b1
`define     Msg_Arg_SDSendCmd_DatInType_512_Bits                50:50
`define     Msg_Arg_SDSendCmd_Cmd_Bits                          47:0

`define Msg_Type_SDDatOut                                       `Msg_Type_Len'h03

`define Msg_Type_SDGetStatus                                    `Msg_Type_Len'h04
`define     Resp_Arg_SDGetStatus_CmdDone_Bits                   63:63
`define     Resp_Arg_SDGetStatus_RespDone_Bits                  62:62
`define         Resp_Arg_SDGetStatus_RespCRCErr_Bits            61:61
`define         Resp_Arg_SDGetStatus_Resp_Bits                  60:13
`define         Resp_Arg_SDGetStatus_Resp_Len                   48
`define     Resp_Arg_SDGetStatus_DatOutDone_Bits                12:12
`define         Resp_Arg_SDGetStatus_DatOutCRCErr_Bits          11:11
`define     Resp_Arg_SDGetStatus_DatInDone_Bits                 10:10
`define         Resp_Arg_SDGetStatus_DatInCRCErr_Bits           9:9
`define         Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits   8:5
`define     Resp_Arg_SDGetStatus_Dat0Idle_Bits                  4:4
`define     Resp_Arg_SDGetStatus_Filler_Bits                    3:0

`define Msg_Type_PixI2CTransaction                              `Msg_Type_Len'h05
`define     Msg_Arg_PixI2CTransaction_Write_Bits                63:63
`define     Msg_Arg_PixI2CTransaction_DataLen_Bits              62:62
`define         Msg_Arg_PixI2CTransaction_DataLen_1             1'b0
`define         Msg_Arg_PixI2CTransaction_DataLen_2             1'b1
`define     Msg_Arg_PixI2CTransaction_RegAddr_Bits              31:16
`define     Msg_Arg_PixI2CTransaction_WriteData_Bits            15:0

`define Msg_Type_PixI2CGetStatus                                `Msg_Type_Len'h06
`define     Msg_Arg_PixI2CGetStatus_Done_Bits                   63:63
`define     Msg_Arg_PixI2CGetStatus_Err_Bits                    62:62
`define     Msg_Arg_PixI2CGetStatus_ReadData_Bits               15:0

`define Msg_Type_SDAbort                                        `Msg_Type_Len'h07
`define Msg_Type_NoOp                                           `Msg_Type_Len'hFF








module Top(
    input wire          clk24mhz,
    
    input wire          ctrl_clk,
    input wire          ctrl_rst,
    input wire          ctrl_di,
    output wire         ctrl_do,
    
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    
    input wire          pix_dclk,
    input wire[11:0]    pix_d,
    input wire          pix_fv,
    input wire          pix_lv,
    output wire         pix_rst_,
    output wire         pix_sclk,
    inout wire          pix_sdata
    
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
    reg         sd_ctrl_clkSlowEn = 0;
    reg         sd_ctrl_clkFastEn = 0;
    reg[3:0]    sd_ctrl_clkDelay = 0;
    
    reg[47:0]   sd_ctrl_cmd = 0;
    reg         sd_ctrl_cmdRespType_48 = 0;
    reg         sd_ctrl_cmdRespType_136 = 0;
    reg         sd_ctrl_cmdDatInType_512 = 0;
    reg         sd_ctrl_cmdTrigger = 0;
    
    reg         sd_ctrl_abort = 0;
    
    wire        sd_datOut_writeClk;
    reg         sd_datOut_writeTrigger = 0;
    reg[15:0]   sd_datOut_writeData = 0;
    wire        sd_datOut_writeOK;
    
    wire        sd_status_cmdDone;
    wire        sd_status_respDone;
    wire        sd_status_respCRCErr;
    wire[47:0]  sd_status_resp;
    wire        sd_status_datOutDone;
    wire        sd_status_datOutCRCErr;
    wire        sd_status_datInDone;
    wire        sd_status_datInCRCErr;
    wire[3:0]   sd_status_datInCMD6AccessMode;
    wire        sd_status_dat0Idle;
    
    SDController #(
        .ClkFreq(ClkFreq)
    ) SDController (
        .clk(clk),
    
        .sdcard_clk(sd_clk),
        .sdcard_cmd(sd_cmd),
        .sdcard_dat(sd_dat),
        
        .ctrl_clkSlowEn(sd_ctrl_clkSlowEn),
        .ctrl_clkFastEn(sd_ctrl_clkFastEn),
        .ctrl_clkDelay(sd_ctrl_clkDelay),
        
        .ctrl_cmd(sd_ctrl_cmd),
        .ctrl_cmdRespType_48(sd_ctrl_cmdRespType_48),
        .ctrl_cmdRespType_136(sd_ctrl_cmdRespType_136),
        .ctrl_cmdDatInType_512(sd_ctrl_cmdDatInType_512),
        .ctrl_cmdTrigger(sd_ctrl_cmdTrigger),
        
        .ctrl_abort(sd_ctrl_abort),
        
        .datOut_writeClk(sd_datOut_writeClk),
        .datOut_writeTrigger(sd_datOut_writeTrigger),
        .datOut_writeData(sd_datOut_writeData),
        .datOut_writeOK(sd_datOut_writeOK),
        
        .status_cmdDone(sd_status_cmdDone),
        .status_respDone(sd_status_respDone),
        .status_respCRCErr(sd_status_respCRCErr),
        .status_resp(sd_status_resp),
        .status_datOutDone(sd_status_datOutDone),
        .status_datOutCRCErr(sd_status_datOutCRCErr),
        .status_datInDone(sd_status_datInDone),
        .status_datInCRCErr(sd_status_datInCRCErr),
        .status_datInCMD6AccessMode(sd_status_datInCMD6AccessMode),
        .status_dat0Idle(sd_status_dat0Idle)
    );
    
    
    
    
    
    
    // ====================
    // PixI2CMaster
    // ====================
    localparam PixI2CSlaveAddr = 7'h10;
    reg pixi2c_cmd_write = 0;
    reg[15:0] pixi2c_cmd_regAddr = 0;
    reg[15:0] pixi2c_cmd_writeData = 0;
    reg pixi2c_cmd_dataLen = 0;
    reg pixi2c_cmd_trigger = 0;
    wire pixi2c_status_done;
    wire pixi2c_status_err;
    wire[15:0] pixi2c_status_readData;
    
    PixI2CMaster #(
        .ClkFreq(24_000_000),
        .I2CClkFreq(400_000) // TODO: we may need to slow this down depending on the strength of the pullup resistor
    ) PixI2CMaster (
        .clk(clk),
        
        .cmd_slaveAddr(PixI2CSlaveAddr),
        .cmd_write(pixi2c_cmd_write),
        .cmd_regAddr(pixi2c_cmd_regAddr),
        .cmd_writeData(pixi2c_cmd_writeData),
        .cmd_dataLen(pixi2c_cmd_dataLen),
        .cmd_trigger(pixi2c_cmd_trigger), // Toggle
        
        .status_done(pixi2c_status_done), // Toggle
        .status_err(pixi2c_status_err),
        .status_readData(pixi2c_status_readData),
        
        .i2c_clk(pix_sclk),
        .i2c_data(pix_sdata)
    );
    
    
    
    
    
    
    
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
    
    `ToggleAck(ctrl_sdCmdDone_, ctrl_sdCmdDoneAck, sd_status_cmdDone, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdRespDone_, ctrl_sdRespDoneAck, sd_status_respDone, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatOutDone_, ctrl_sdDatOutDoneAck, sd_status_datOutDone, posedge, ctrl_clk);
    `ToggleAck(ctrl_sdDatInDone_, ctrl_sdDatInDoneAck, sd_status_datInDone, posedge, ctrl_clk);
    
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
                    $display("[CTRL] Got Msg_Type_Echo: %0h", ctrl_msgArg);
                    ctrl_doutReg[`Resp_Arg_Bits] <= {ctrl_msgArg, 8'h00};
                    // ctrl_doutReg[`Resp_Arg_Bits] <= 'b10000;
                end
                
                // Set SD clock source
                `Msg_Type_SDClkSet: begin
                    $display("[CTRL] Got Msg_Type_SDClkSet: delay=%0d fast=%b slow=%b",
                        ctrl_msgArg[`Msg_Arg_SDClkSet_ClkDelay_Bits],
                        ctrl_msgArg[`Msg_Arg_SDClkSet_ClkSrc_Fast_Bits],
                        ctrl_msgArg[`Msg_Arg_SDClkSet_ClkSrc_Slow_Bits]);
                    
                    // We don't need to synchronize `sd_ctrl_clkDelay` into the sd_ domain,
                    // because it should only be set while the sd_ clock is disabled.
                    sd_ctrl_clkDelay <= ctrl_msgArg[`Msg_Arg_SDClkSet_ClkDelay_Bits];
                    sd_ctrl_clkFastEn <= ctrl_msgArg[`Msg_Arg_SDClkSet_ClkSrc_Fast_Bits];
                    sd_ctrl_clkSlowEn <= ctrl_msgArg[`Msg_Arg_SDClkSet_ClkSrc_Slow_Bits];
                end
                
                // Clock out SD command
                `Msg_Type_SDSendCmd: begin
                    $display("[CTRL] Got Msg_Type_SDSendCmd");
                    // Clear our signals so they can be reliably observed via SDGetStatus
                    if (!ctrl_sdCmdDone_) ctrl_sdCmdDoneAck <= !ctrl_sdCmdDoneAck;
                    
                    // Reset `ctrl_sdRespDone_` if the Resp state machine will run
                    if (ctrl_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits] !== `Msg_Arg_SDSendCmd_RespType_0) begin
                        if (!ctrl_sdRespDone_) ctrl_sdRespDoneAck <= !ctrl_sdRespDoneAck;
                    end
                    
                    // Reset `ctrl_sdDatInDone_` if the DatIn state machine will run
                    if (ctrl_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits] !== `Msg_Arg_SDSendCmd_DatInType_0) begin
                        if (!ctrl_sdDatInDone_) ctrl_sdDatInDoneAck <= !ctrl_sdDatInDoneAck;
                    end
                    
                    sd_ctrl_cmdRespType_48 <= ctrl_msgArg[`Msg_Arg_SDSendCmd_RespType_48_Bits];
                    sd_ctrl_cmdRespType_136 <= ctrl_msgArg[`Msg_Arg_SDSendCmd_RespType_136_Bits];
                    sd_ctrl_cmdDatInType_512 <= ctrl_msgArg[`Msg_Arg_SDSendCmd_DatInType_512_Bits];
                    
                    sd_ctrl_cmd <= ctrl_msgArg[`Msg_Arg_SDSendCmd_Cmd_Bits];
                    sd_ctrl_cmdTrigger <= !sd_ctrl_cmdTrigger;
                end
                
                `Msg_Type_SDDatOut: begin
                    $display("[CTRL] Got Msg_Type_SDDatOut");
                    if (!ctrl_sdDatOutDone_) ctrl_sdDatOutDoneAck <= !ctrl_sdDatOutDoneAck;
                    // TODO: trigger dat out
                end
                
                // Get SD status / response
                `Msg_Type_SDGetStatus: begin
                    $display("[CTRL] Got Msg_Type_SDGetStatus");
                    
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_CmdDone_Bits] <= !ctrl_sdCmdDone_;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_RespDone_Bits] <= !ctrl_sdRespDone_;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_RespCRCErr_Bits] <= sd_status_respCRCErr;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_DatOutDone_Bits] <= !ctrl_sdDatOutDone_;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_DatOutCRCErr_Bits] <= sd_status_datOutCRCErr;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_DatInDone_Bits] <= !ctrl_sdDatInDone_;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_DatInCRCErr_Bits] <= sd_status_datInCRCErr;
                        ctrl_doutReg[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits] <= sd_status_datInCMD6AccessMode;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_Dat0Idle_Bits] <= ctrl_sdDat0Idle;
                    ctrl_doutReg[`Resp_Arg_SDGetStatus_Resp_Bits] <= sd_status_resp;
                end
                
                `Msg_Type_SDAbort: begin
                    $display("[CTRL] Got Msg_Type_SDAbort");
                    sd_ctrl_abort <= !sd_ctrl_abort;
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
    tri1        sd_cmd;
    tri1[3:0]   sd_dat;
    
    reg         pix_dclk;
    reg[11:0]   pix_d;
    reg         pix_fv;
    reg         pix_lv;
    wire        pix_rst_;
    wire        pix_sclk;
    wire        pix_sdata;
    
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
    
    task SendSDCmd(input[5:0] sdCmd, input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType, input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg[`Msg_Arg_Len-1] arg;
        arg = 0;
        arg[`Msg_Arg_SDSendCmd_RespType_Bits] = respType;
        arg[`Msg_Arg_SDSendCmd_DatInType_Bits] = datInType;
        arg[`Msg_Arg_SDSendCmd_Cmd_Bits] = {2'b01, sdCmd, sdArg, 7'b0, 1'b1};
        
        SendMsg(`Msg_Type_SDSendCmd, arg);
    end endtask
    
    task SendSDCmdResp(input[5:0] sdCmd, input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType, input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg done;
        SendSDCmd(sdCmd, respType, datInType, sdArg);
        
        // Wait for SD command to be sent
        do begin
            // Request SD status
            SendMsgResp(`Msg_Type_SDGetStatus, 0);
            
            // If a response is expected, we're done when the response is received
            if (respType !== `Msg_Arg_SDSendCmd_RespType_0) done = resp[`Resp_Arg_SDGetStatus_RespDone_Bits];
            // If a response isn't expected, we're done when the command is sent
            else done = resp[`Resp_Arg_SDGetStatus_CmdDone_Bits];
        end while(!done);
    end endtask
    
    initial begin
        reg[15:0] i, ii;
        reg done;
        reg[`Resp_Arg_SDGetStatus_Resp_Len-1:0] sdResp;
        
        // Set our initial state
        ctrl_clk = 0;
        ctrl_rst = 1;
        ctrl_diReg = ~0;
        #1;
        
        // // ====================
        // // Test NoOp command
        // // ====================
        //
        // SendMsgResp(`Msg_Type_NoOp, 56'h66554433221100);
        // $display("Got response: %h", resp);
        // `Finish;
        
        
        
        
        
        // // ====================
        // // Test Echo command
        // // ====================
        //
        // SendMsgResp(`Msg_Type_Echo, `Msg_Arg_Len'h66554433221100);
        // $display("Got response: %h", resp);
        // `Finish;
        
        
        
        

        // // ====================
        // // Test SD CMD8 (SEND_IF_COND)
        // // ====================
        //
        // // Set SD clock source = slow clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_Slow);
        //
        // // Send SD CMD0
        // SendSDCmdResp(CMD0, `Msg_Arg_SDSendCmd_RespType_0, `Msg_Arg_SDSendCmd_DatInType_0, 0);
        //
        // // Send SD CMD8
        // SendSDCmdResp(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_0, 32'h000001AA);
        // if (resp[`Resp_Arg_SDGetStatus_RespCRCErr_Bits] !== 1'b0) begin
        //     $display("[EXT] CRC error ❌");
        //     `Finish;
        // end
        //
        // sdResp = resp[`Resp_Arg_SDGetStatus_Resp_Bits];
        // if (sdResp[15:8] !== 8'hAA) begin
        //     $display("[EXT] Bad response: %h ❌", resp);
        //     `Finish;
        // end
        //
        // `Finish;
        
        
        
        
        
        // // ====================
        // // Test writing data to SD card / DatOut
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_Fast);
        //
        // // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        // SendSDCmdResp(CMD55, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_0, 32'b0);
        // SendSDCmdResp(ACMD23, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_0, 32'b1);
        //
        // // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        // SendSDCmdResp(CMD25, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_0, 32'b0);
        //
        // // Clock out data on DAT lines
        // SendMsg(`Msg_Type_SDDatOut, 0);
        //
        // // Wait until we're done clocking out data on DAT lines
        // $display("[EXT] Waiting while data is written...");
        // do begin
        //     // Request SD status
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        // end while(!resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits]);
        // $display("[EXT] Done writing (SD resp: %b)", resp[`Resp_Arg_SDGetStatus_Resp_Bits]);
        //
        // // Check CRC status
        // if (resp[`Resp_Arg_SDGetStatus_DatOutCRCErr_Bits] === 1'b0) begin
        //     $display("[EXT] DatOut CRC OK ✅");
        // end else begin
        //     $display("[EXT] DatOut CRC bad ❌");
        // end
        // `Finish;

        
        
        
        
        
        
        
        
        
        // // ====================
        // // Test CMD6 (SWITCH_FUNC) + DatIn
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_Fast);
        //
        // // Send SD command CMD6 (SWITCH_FUNC)
        // SendSDCmdResp(CMD6, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 32'h80FFFFF3);
        // $display("[EXT] Waiting for DatIn to complete...");
        // do begin
        //     // Request SD status
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        // end while(!resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        // $display("[EXT] DatIn completed");
        //
        // // Check DatIn CRC status
        // if (resp[`Resp_Arg_SDGetStatus_DatInCRCErr_Bits] === 1'b0) begin
        //     $display("[EXT] DatIn CRC OK ✅");
        // end else begin
        //     $display("[EXT] DatIn CRC bad ❌");
        // end
        //
        // // Check the access mode from the CMD6 response
        // if (resp[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits] === 4'h3) begin
        //     $display("[EXT] CMD6 access mode == 0x3 ✅");
        // end else begin
        //     $display("[EXT] CMD6 access mode == 0x%h ❌", resp[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits]);
        // end
        // `Finish;
        
        
        
        
        
        
        
        // // ====================
        // // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
        // //   Note: we expect CRC errors in the response because the R2
        // //   response CRC doesn't follow the semantics of other responses
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_None);
        //
        // // Set SD clock source = slow clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_Slow);
        //
        // // Send SD command CMD2 (ALL_SEND_CID)
        // SendSDCmdResp(CMD2, `Msg_Arg_SDSendCmd_RespType_136, `Msg_Arg_SDSendCmd_DatInType_0, 0);
        // $display("====================================================");
        // $display("^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        // $display("====================================================");
        // `Finish;
        
        
        
        
        
        
        
        
        
        // // ====================
        // // Test Resp abort
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_Fast);
        //
        // // Send an SD command that doesn't provide a response
        // SendSDCmd(CMD0, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_0, 0);
        // $display("[EXT] Verifying that Resp times out...");
        // done = 0;
        // for (i=0; i<10 && !done; i++) begin
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //     $display("[EXT] Pre-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //         i+1,
        //         resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        //
        //     done = resp[`Resp_Arg_SDGetStatus_RespDone_Bits];
        // end
        //
        // if (!done) begin
        //     $display("[EXT] Resp timeout ✅");
        //     $display("[EXT] Aborting...");
        //     SendMsg(`Msg_Type_SDAbort, 0);
        //
        //     $display("[EXT] Checking abort status...");
        //     done = 0;
        //     for (i=0; i<10 && !done; i++) begin
        //         SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //         $display("[EXT] Post-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //             i+1,
        //             resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        //
        //         done =  resp[`Resp_Arg_SDGetStatus_CmdDone_Bits]     &&
        //                 resp[`Resp_Arg_SDGetStatus_RespDone_Bits]    &&
        //                 resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits]  &&
        //                 resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]   ;
        //     end
        //
        //     if (done) begin
        //         $display("[EXT] Abort OK ✅");
        //     end else begin
        //         $display("[EXT] Abort failed ❌");
        //     end
        //
        // end else begin
        //     $display("[EXT] DatIn didn't timeout? ❌");
        // end
        // `Finish;
        
        
        
        
        
        
        
        
        // // ====================
        // // Test DatOut abort
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_Fast);
        //
        // // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        // SendSDCmdResp(CMD25, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_0, 32'b0);
        //
        // // Clock out data on DAT lines
        // SendMsg(`Msg_Type_SDDatOut, 0);
        //
        // // Verify that we timeout
        // $display("[EXT] Verifying that DatOut times out...");
        // done = 0;
        // for (i=0; i<10 && !done; i++) begin
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //     $display("[EXT] Pre-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //         i+1,
        //         resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        //
        //     done = resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits];
        // end
        //
        // if (!done) begin
        //     $display("[EXT] DatOut timeout ✅");
        //     $display("[EXT] Aborting...");
        //     SendMsg(`Msg_Type_SDAbort, 0);
        //
        //     $display("[EXT] Checking abort status...");
        //     done = 0;
        //     for (i=0; i<10 && !done; i++) begin
        //         SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //         $display("[EXT] Post-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //             i+1,
        //             resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        //
        //         done =  resp[`Resp_Arg_SDGetStatus_CmdDone_Bits]     &&
        //                 resp[`Resp_Arg_SDGetStatus_RespDone_Bits]    &&
        //                 resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits]  &&
        //                 resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]   ;
        //     end
        //
        //     if (done) begin
        //         $display("[EXT] Abort OK ✅");
        //     end else begin
        //         $display("[EXT] Abort failed ❌");
        //     end
        //
        // end else begin
        //     $display("[EXT] DatOut didn't timeout? ❌");
        // end
        // `Finish;
        
        
        
        
        
        
        
        
        // // ====================
        // // Test DatIn abort
        // // ====================
        //
        // // Disable SD clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_None);
        //
        // // Set SD clock source = fast clock
        // SendMsg(`Msg_Type_SDClkSet, `Msg_Arg_SDClkSet_ClkSrc_Fast);
        //
        // // Send SD command that doesn't respond on the DAT lines,
        // // but specify that we expect DAT data
        // SendSDCmdResp(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 0);
        // $display("[EXT] Verifying that DatIn times out...");
        // done = 0;
        // for (i=0; i<10 && !done; i++) begin
        //     SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //     $display("[EXT] Pre-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //         i+1,
        //         resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
        //         resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        //     done = resp[`Resp_Arg_SDGetStatus_DatInDone_Bits];
        // end
        //
        // if (!done) begin
        //     $display("[EXT] DatIn timeout ✅");
        //     $display("[EXT] Aborting...");
        //     SendMsg(`Msg_Type_SDAbort, 0);
        //
        //     $display("[EXT] Checking abort status...");
        //     done = 0;
        //     for (i=0; i<10 && !done; i++) begin
        //         SendMsgResp(`Msg_Type_SDGetStatus, 0);
        //         $display("[EXT] Post-abort status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
        //             i+1,
        //             resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
        //             resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        //
        //         done =  resp[`Resp_Arg_SDGetStatus_CmdDone_Bits]     &&
        //                 resp[`Resp_Arg_SDGetStatus_RespDone_Bits]    &&
        //                 resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits]  &&
        //                 resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]   ;
        //     end
        //
        //     if (done) begin
        //         $display("[EXT] Abort OK ✅");
        //     end else begin
        //         $display("[EXT] Abort failed ❌");
        //     end
        //
        // end else begin
        //     $display("[EXT] DatIn didn't timeout? ❌");
        // end
        // `Finish;
    end
endmodule
`endif
