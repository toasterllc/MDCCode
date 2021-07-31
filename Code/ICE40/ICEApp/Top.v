`include "Util.v"
`include "Sync.v"
`include "ToggleAck.v"
`include "SDController.v"
`include "ICEAppTypes.v"
`include "ClockGen.v"

`ifdef SIM
`include "SDCardSim.v"
`endif

`timescale 1ns/1ps

module Top(
    input wire          ice_img_clk16mhz,
    
    input wire          ice_msp_spi_clk,
    inout wire          ice_msp_spi_data,
    
    output wire         sd_clk,
    inout wire          sd_cmd,
    inout wire[3:0]     sd_dat,
    
`ifdef SIM
    output wire         sim_rst_, // Exported so that the sim can verify that the state machine is in reset
`endif
    
    output reg[3:0]     ice_led = 0
);
    // ====================
    // SD Clock (102 MHz)
    // ====================
    localparam SD_Clk_Freq = 102_000_000;
    wire sd_clk_int;
    ClockGen #(
        .FREQOUT(SD_Clk_Freq),
        .DIVR(0),
        .DIVF(50),
        .DIVQ(3),
        .FILTER_RANGE(1)
    ) ClockGen_sd_clk_int(.clkRef(ice_img_clk16mhz), .clk(sd_clk_int));
    
    // ====================
    // SDController
    // ====================
    reg         sd_config_init_rst = 0;
    reg         sd_config_init_trigger = 0;
    wire        sd_config_init_done;
    reg[1:0]    sd_config_clkSrc_speed = 0;
    reg[3:0]    sd_config_clkSrc_delay = 0;
    reg         sd_cmd_trigger = 0;
    reg[47:0]   sd_cmd_data = 0;
    reg[1:0]    sd_cmd_respType = 0;
    reg         sd_cmd_datInType = 0;
    wire        sd_cmd_done;
    wire        sd_resp_done;
    wire[47:0]  sd_resp_data;
    wire        sd_resp_crcErr;
    reg         sd_datOut_stop = 0;
    wire        sd_datOut_stopped;
    reg         sd_datOut_start = 0;
    wire        sd_datOut_ready;
    wire        sd_datOut_done;
    wire        sd_datOut_crcErr;
    wire        sd_datOutRead_clk;
    wire        sd_datOutRead_ready;
    wire        sd_datOutRead_trigger;
    wire[15:0]  sd_datOutRead_data;
    wire        sd_datIn_done;
    wire        sd_datIn_crcErr;
    wire[3:0]   sd_datIn_cmd6AccessMode;
    wire        sd_status_dat0Idle;
    
    SDController #(
        .ClkFreq(SD_Clk_Freq)
    ) SDController (
        .clk(sd_clk_int),
        
        .sd_clk(sd_clk),
        .sd_cmd(sd_cmd),
        .sd_dat(sd_dat),
        
        .config_init_rst(sd_config_init_rst),
        .config_init_trigger(sd_config_init_trigger),
        .config_init_done(sd_config_init_done),
        .config_clkSrc_speed(sd_config_clkSrc_speed),
        .config_clkSrc_delay(sd_config_clkSrc_delay),
        
        .cmd_trigger(sd_cmd_trigger),
        .cmd_data(sd_cmd_data),
        .cmd_respType(sd_cmd_respType),
        .cmd_datInType(sd_cmd_datInType),
        .cmd_done(sd_cmd_done),
        
        .resp_done(sd_resp_done),
        .resp_data(sd_resp_data),
        .resp_crcErr(sd_resp_crcErr),
        
        .datOut_stop(sd_datOut_stop),
        .datOut_stopped(sd_datOut_stopped),
        .datOut_start(sd_datOut_start),
        .datOut_done(sd_datOut_done),
        .datOut_crcErr(sd_datOut_crcErr),
        
        .datOutRead_clk(sd_datOutRead_clk),
        .datOutRead_ready(sd_datOutRead_ready),
        .datOutRead_trigger(sd_datOutRead_trigger),
        .datOutRead_data(sd_datOutRead_data),
        
        .datIn_done(sd_datIn_done),
        .datIn_crcErr(sd_datIn_crcErr),
        .datIn_cmd6AccessMode(sd_datIn_cmd6AccessMode),
        
        .status_dat0Idle(sd_status_dat0Idle)
    );
    
    
    
    
    
    
    
    // ====================
    // spi_clk
    // ====================
    wire spi_clk = ice_msp_spi_clk;
    
    // ====================
    // spi_rst_ Generation
    // ====================
    localparam SPIRstClkFreqHz = 16000000;
    // Our math is such that asserting `spi_clk` for 2x `SPIRstActivateThresholdUs`
    // is guaranteed to trigger a reset.
    // This is because we size `spirst_counter` to fit `SPIRstActivateThresholdUs`,
    // but `spi_rst_` is only asserted when all bits in `spirst_counter` are 1,
    // which will likely be >SPIRstTicks, since SPIRstTicks likely isn't a power
    // of 2.
    localparam SPIRstActivateThresholdUs = 5;
    localparam SPIRstTicks = (SPIRstClkFreqHz*SPIRstActivateThresholdUs)/1000000;
    wire spirst_clk = ice_img_clk16mhz;
    reg[`RegWidth(SPIRstTicks-1)-1:0] spirst_counter = 0;
    `Sync(spirst_spiClkSynced, spi_clk, posedge, spirst_clk);
    wire spi_rst_ = !(&spirst_counter);
    always @(posedge spirst_clk) begin
        spirst_counter <= spirst_counter;
        if (!spirst_spiClkSynced) begin
            spirst_counter <= 0;
        end else if (spi_rst_) begin
            spirst_counter <= spirst_counter+1;
        end
    end
`ifdef SIM
    assign sim_rst_ = spi_rst_;
`endif
    
    // ====================
    // SPI State Machine
    // ====================
    
    // SD nets
    `ToggleAck(spi_sdInitDone_, spi_sdInitDoneAck, sd_config_init_done, posedge, spi_clk);
    `ToggleAck(spi_sdCmdDone_, spi_sdCmdDoneAck, sd_cmd_done, posedge, spi_clk);
    `ToggleAck(spi_sdRespDone_, spi_sdRespDoneAck, sd_resp_done, posedge, spi_clk);
    `ToggleAck(spi_sdDatOutDone_, spi_sdDatOutDoneAck, sd_datOut_done, posedge, spi_clk);
    `ToggleAck(spi_sdDatInDone_, spi_sdDatInDoneAck, sd_datIn_done, posedge, spi_clk);
    `Sync(spi_sdDat0Idle, sd_status_dat0Idle, posedge, spi_clk);
    
    // SPI control nets
    localparam TurnaroundDelay = 8;
    localparam TurnaroundInherentDelay = 4;
    localparam TurnaroundExtraDelay = TurnaroundDelay-TurnaroundInherentDelay;
    localparam MsgCycleCount = `Msg_Len+TurnaroundExtraDelay-2;
    localparam RespCycleCount = `Resp_Len-1;
    
    reg[`Msg_Len-1:0] spi_dataInReg = 0;
    wire[`Msg_Type_Len-1:0] spi_msgType = spi_dataInReg[`Msg_Type_Bits];
    wire[`Msg_Arg_Len-1:0] spi_msgArg = spi_dataInReg[`Msg_Arg_Bits];
    reg[`RegWidth2(MsgCycleCount,RespCycleCount)-1:0] spi_dataCounter = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    reg[TurnaroundExtraDelay-1:0] spi_dataInDelayed = 0;
    reg spi_dataOut = 0;
    reg spi_dataOutEn = 0;
    wire spi_dataIn;
    
    localparam SPI_State_MsgIn      = 0;    // +2
    localparam SPI_State_RespOut    = 3;    // +0
    localparam SPI_State_Count      = 4;
    reg[`RegWidth(SPI_State_Count-1)-1:0] spi_state = 0;
    
    always @(posedge spi_clk, negedge spi_rst_) begin
        if (!spi_rst_) begin
            $display("[SPI] Reset");
            spi_state <= 0;
            spi_dataOutEn <= 0;
        
        end else begin
            spi_dataInDelayed <= spi_dataInDelayed<<1|spi_dataIn;
            spi_dataInReg <= spi_dataInReg<<1|`LeftBit(spi_dataInDelayed,0);
            spi_dataCounter <= spi_dataCounter-1;
            spi_dataOutEn <= 0;
            spi_resp <= spi_resp<<1|1'b1;
            spi_dataOut <= `LeftBit(spi_resp, 0);
            
            case (spi_state)
            SPI_State_MsgIn: begin
                // Wait for the start of the message, signified by the first 0 bit
                if (!spi_dataIn) begin
                    spi_dataCounter <= MsgCycleCount;
                    spi_state <= SPI_State_MsgIn+1;
                end
            end
        
            SPI_State_MsgIn+1: begin
                if (!spi_dataCounter) begin
                    spi_state <= SPI_State_MsgIn+2;
                end
            end
        
            SPI_State_MsgIn+2: begin
                // By default, go to SPI_State_Nop
                spi_state <= SPI_State_RespOut;
                spi_dataCounter <= RespCycleCount;
                
                case (spi_msgType)
                // Echo
                `Msg_Type_Echo: begin
                    $display("[SPI] Got Msg_Type_Echo: %0h", spi_msgArg[`Msg_Arg_Echo_Msg_Bits]);
                    // spi_resp <= 64'hxxxxxxxx_xxxxxxxx;
                    // spi_resp <= 64'h12345678_ABCDEF12;
                    spi_resp[`Resp_Arg_Echo_Msg_Bits] <= spi_msgArg[`Msg_Arg_Echo_Msg_Bits];
                end
                
                // LEDSet
                `Msg_Type_LEDSet: begin
                    $display("[SPI] Got Msg_Type_LEDSet: %b", spi_msgArg[`Msg_Arg_LEDSet_Val_Bits]);
                    ice_led <= spi_msgArg[`Msg_Arg_LEDSet_Val_Bits];
                end
                
                // Set SD clock source
                `Msg_Type_SDConfig: begin
                    $display("[SPI] Got Msg_Type_SDConfig: delay=%0d speed=%0d trigger=%0d en=%0d",
                        spi_msgArg[`Msg_Arg_SDConfig_ClkSrc_Delay_Bits],
                        spi_msgArg[`Msg_Arg_SDConfig_ClkSrc_Speed_Bits],
                        spi_msgArg[`Msg_Arg_SDConfig_Init_Trigger_Bits],
                        spi_msgArg[`Msg_Arg_SDConfig_Init_Rst_Bits],
                    );
                    
                    // We don't need to synchronize `sd_clksrc_delay` into the sd_ domain,
                    // because it should only be set while the sd_ clock is disabled.
                    sd_config_clkSrc_delay <= spi_msgArg[`Msg_Arg_SDConfig_ClkSrc_Delay_Bits];
                    
                    case (spi_msgArg[`Msg_Arg_SDConfig_ClkSrc_Speed_Bits])
                    `Msg_Arg_SDConfig_ClkSrc_Speed_Off:    sd_config_clkSrc_speed <= `SDController_Config_ClkSrc_Speed_Off;
                    `Msg_Arg_SDConfig_ClkSrc_Speed_Slow:   sd_config_clkSrc_speed <= `SDController_Config_ClkSrc_Speed_Slow;
                    `Msg_Arg_SDConfig_ClkSrc_Speed_Fast:   sd_config_clkSrc_speed <= `SDController_Config_ClkSrc_Speed_Fast;
                    endcase
                    
                    if (spi_msgArg[`Msg_Arg_SDConfig_Init_Trigger_Bits]) begin
                        sd_config_init_trigger <= !sd_config_init_trigger;
                    end
                    
                    if (spi_msgArg[`Msg_Arg_SDConfig_Init_Rst_Bits]) begin
                        // Reset spi_sdInitDone_
                        if (!spi_sdInitDone_) spi_sdInitDoneAck <= !spi_sdInitDoneAck;
                        sd_config_init_rst <= !sd_config_init_rst;
                    end
                end
                
                // Clock out SD command
                `Msg_Type_SDSendCmd: begin
                    $display("[SPI] Got Msg_Type_SDSendCmd [respType:%0b]", spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]);
                    // Reset spi_sdCmdDone_ / spi_sdRespDone_ / spi_sdDatInDone_
                    if (!spi_sdCmdDone_) spi_sdCmdDoneAck <= !spi_sdCmdDoneAck;
                    
                    if (!spi_sdRespDone_ && spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits]!==`Msg_Arg_SDSendCmd_RespType_None)
                        spi_sdRespDoneAck <= !spi_sdRespDoneAck;
                    
                    if (!spi_sdDatInDone_ && spi_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits]!==`Msg_Arg_SDSendCmd_DatInType_None)
                        spi_sdDatInDoneAck <= !spi_sdDatInDoneAck;
                    
                    case (spi_msgArg[`Msg_Arg_SDSendCmd_RespType_Bits])
                    `Msg_Arg_SDSendCmd_RespType_None:   sd_cmd_respType <= `SDController_RespType_None;
                    `Msg_Arg_SDSendCmd_RespType_48:     sd_cmd_respType <= `SDController_RespType_48;
                    `Msg_Arg_SDSendCmd_RespType_136:    sd_cmd_respType <= `SDController_RespType_136;
                    endcase
                    
                    case (spi_msgArg[`Msg_Arg_SDSendCmd_DatInType_Bits])
                    `Msg_Arg_SDSendCmd_DatInType_None:  sd_cmd_datInType <= `SDController_DatInType_None;
                    `Msg_Arg_SDSendCmd_DatInType_512:   sd_cmd_datInType <= `SDController_DatInType_512;
                    endcase
                    
                    sd_cmd_data <= spi_msgArg[`Msg_Arg_SDSendCmd_CmdData_Bits];
                    sd_cmd_trigger <= !sd_cmd_trigger;
                end
                
                // Get SD status / response
                `Msg_Type_SDGetStatus: begin
                    $display("[SPI] Got Msg_Type_SDGetStatus");
                    spi_resp[`Resp_Arg_SDGetStatus_InitDone_Bits] <= !spi_sdInitDone_;
                    spi_resp[`Resp_Arg_SDGetStatus_CmdDone_Bits] <= !spi_sdCmdDone_;
                    spi_resp[`Resp_Arg_SDGetStatus_RespDone_Bits] <= !spi_sdRespDone_;
                        spi_resp[`Resp_Arg_SDGetStatus_RespCRCErr_Bits] <= sd_resp_crcErr;
                    spi_resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits] <= !spi_sdDatOutDone_;
                        spi_resp[`Resp_Arg_SDGetStatus_DatOutCRCErr_Bits] <= sd_datOut_crcErr;
                    spi_resp[`Resp_Arg_SDGetStatus_DatInDone_Bits] <= !spi_sdDatInDone_;
                        spi_resp[`Resp_Arg_SDGetStatus_DatInCRCErr_Bits] <= sd_datIn_crcErr;
                        spi_resp[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits] <= sd_datIn_cmd6AccessMode;
                    spi_resp[`Resp_Arg_SDGetStatus_Dat0Idle_Bits] <= spi_sdDat0Idle;
                    spi_resp[`Resp_Arg_SDGetStatus_Resp_Bits] <= sd_resp_data;
                end
                
                `Msg_Type_NoOp: begin
                    $display("[SPI] Got Msg_Type_None");
                end
                
                default: begin
                    $display("[SPI] BAD COMMAND: %0d ❌", spi_msgType);
                    `Finish;
                end
                endcase
            end
            
            SPI_State_RespOut: begin
                spi_dataOutEn <= 1;
                if (!spi_dataCounter) begin
                    spi_state <= SPI_State_MsgIn;
                end
            end
            endcase
        end
    end
    
    // ====================
    // Pin: ice_msp_spi_data
    // ====================
    SB_IO #(
        .PIN_TYPE(6'b1101_00),
        .PULLUP(1'b1)
    ) SB_IO_ice_msp_spi_data (
        .INPUT_CLK(ice_msp_spi_clk),
        .OUTPUT_CLK(ice_msp_spi_clk),
        .PACKAGE_PIN(ice_msp_spi_data),
        .OUTPUT_ENABLE(spi_dataOutEn),
        .D_OUT_0(spi_dataOut),
        .D_IN_0(spi_dataIn)
    );
    
endmodule







`ifdef SIM
module Testbench();
    reg ice_img_clk16mhz = 0;
    reg ice_msp_spi_clk = 0;
    wire ice_msp_spi_data;
    
    wire sd_clk;
    wire sd_cmd;
    wire[3:0] sd_dat;
    
    wire[3:0] ice_led;
    wire sim_rst_;
    
    initial begin
        forever begin
            ice_img_clk16mhz = ~ice_img_clk16mhz;
            #32;
        end
    end
    
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
    
    reg[`Msg_Len-1:0] spi_dataOutReg = 0;
    reg[`Resp_Len-1:0] spi_resp = 0;
    
    reg spi_dataOutEn = 0;    
    wire spi_dataIn = ice_msp_spi_data;
    assign ice_msp_spi_data = (spi_dataOutEn ? `LeftBit(spi_dataOutReg, 0) : 1'bz);
    
    // localparam ice_msp_spi_clk_HALF_PERIOD = 32; // 16 MHz
    localparam ice_msp_spi_clk_HALF_PERIOD = 1024; // 1 MHz
    task SendMsg(input[`Msg_Type_Len-1:0] typ, input[`Msg_Arg_Len-1:0] arg); begin
        reg[15:0] i;
        
        spi_dataOutReg = {typ, arg};
        spi_dataOutEn = 1;
        
        for (i=0; i<`Msg_Len; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
            
            spi_dataOutReg = spi_dataOutReg<<1|1'b1;
        end
        
        spi_dataOutEn = 0;
        
        // Turnaround delay cycles
        for (i=0; i<8; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
        end
        
        // Clock in response
        for (i=0; i<`Resp_Len; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            
                spi_resp = spi_resp<<1|spi_dataIn;
            
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
        end
    end endtask
    
    task TestRst; begin
        $display("\n[Testbench] ========== TestRst ==========");
        
        $display("[Testbench] ice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #10000;
        
        if (sim_rst_ === 1'b1) begin
            $display("[Testbench] sim_rst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b1 ❌");
            `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 1");
        ice_msp_spi_clk = 1;
        #10000;
        
        if (sim_rst_ === 1'b0) begin
            $display("[Testbench] sim_rst_ === 1'b0 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b0 ❌");
            `Finish;
        end
        
        $display("\n[Testbench] ice_msp_spi_clk = 0");
        ice_msp_spi_clk = 0;
        #10000;
        
        if (sim_rst_ === 1'b1) begin
            $display("[Testbench] sim_rst_ === 1'b1 ✅");
        end else begin
            $display("[Testbench] sim_rst_ !== 1'b1 ❌");
            `Finish;
        end
        
    end endtask
    
    task TestNoOp; begin
        $display("\n[Testbench] ========== TestNoOp ==========");
        SendMsg(`Msg_Type_NoOp, 56'hFFFFFFFFFFFFFF);
        if (spi_resp === 64'hxxxxxxxxxxxxxxxx) begin
            $display("[Testbench] Response OK: %h ✅", spi_resp);
        end else begin
            $display("[Testbench] Bad response: %h ❌", spi_resp);
            `Finish;
        end
    end endtask
    
    task TestEcho(input[`Msg_Arg_Echo_Msg_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[Testbench] ========== TestEcho ==========");
        arg[`Msg_Arg_Echo_Msg_Bits] = val;
        
        SendMsg(`Msg_Type_Echo, arg);
        if (spi_resp[`Resp_Arg_Echo_Msg_Bits] === val) begin
            $display("[Testbench] Response OK: %h ✅", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
        end else begin
            $display("[Testbench] Bad response: %h ❌", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
            `Finish;
        end
    end endtask
    
    task TestLEDSet(input[`Msg_Arg_LEDSet_Val_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[Testbench] ========== TestLEDSet ==========");
        arg[`Msg_Arg_LEDSet_Val_Bits] = val;
        
        SendMsg(`Msg_Type_LEDSet, arg);
        if (ice_led === val) begin
            $display("[Testbench] ice_led matches (%b) ✅", ice_led);
        end else begin
            $display("[Testbench] ice_led doesn't match (expected: %b, got: %b) ❌", val, ice_led);
            `Finish;
        end
    end endtask
    
    
    
    
    
    
    
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
    
    task SendSDCmd(input[5:0] sdCmd, input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType, input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg[`Msg_Arg_Len-1] arg;
        arg = 0;
        arg[`Msg_Arg_SDSendCmd_RespType_Bits] = respType;
        arg[`Msg_Arg_SDSendCmd_DatInType_Bits] = datInType;
        arg[`Msg_Arg_SDSendCmd_CmdData_Bits] = {2'b01, sdCmd, sdArg, 7'b0, 1'b1};
        
        SendMsg(`Msg_Type_SDSendCmd, arg);
    end endtask
    
    task SendSDCmdResp(input[5:0] sdCmd, input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType, input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType, input[31:0] sdArg); begin
        reg[15:0] i;
        reg done;
        SendSDCmd(sdCmd, respType, datInType, sdArg);
        
        // Wait for SD command to be sent
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            // Request SD status
            SendMsg(`Msg_Type_SDGetStatus, 0);
            
            // We're done when the SD command is sent
            done = spi_resp[`Resp_Arg_SDGetStatus_CmdDone_Bits];
            // If a response is expected, we're done when the response is received
            if (respType !== `Msg_Arg_SDSendCmd_RespType_None) done &= spi_resp[`Resp_Arg_SDGetStatus_RespDone_Bits];
            if (datInType !== `Msg_Arg_SDSendCmd_DatInType_None) done &= spi_resp[`Resp_Arg_SDGetStatus_DatInDone_Bits];
        end
        
        if (!done) begin
            $display("[Testbench] SD card response timeout ❌");
            `Finish;
        end
    end endtask
    
    task TestSDConfig(
        input[`Msg_Arg_SDConfig_ClkSrc_Delay_Len-1:0] delay,
        input[`Msg_Arg_SDConfig_ClkSrc_Speed_Len-1:0] speed,
        input[`Msg_Arg_SDConfig_Init_Trigger_Len-1:0] trigger,
        input[`Msg_Arg_SDConfig_Init_Rst_Len-1:0] rst
    ); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        // $display("\n[Testbench] ========== TestSDConfig ==========");
        arg[`Msg_Arg_SDConfig_ClkSrc_Delay_Bits] = delay;
        arg[`Msg_Arg_SDConfig_ClkSrc_Speed_Bits] = speed;
        arg[`Msg_Arg_SDConfig_Init_Trigger_Bits] = trigger;
        arg[`Msg_Arg_SDConfig_Init_Rst_Bits] = rst;
        
        SendMsg(`Msg_Type_SDConfig, arg);
    end endtask
    
    task TestSDInit; begin
        reg[15:0] i;
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;
        
        $display("\n[Testbench] ========== TestSDInit ==========");
        
        TestSDConfig(0, `Msg_Arg_SDConfig_ClkSrc_Speed_Off,  0, 0); // Disable SD clock, enable SD init mode
        TestSDConfig(0, `Msg_Arg_SDConfig_ClkSrc_Speed_Slow, 0, 0); // SD clock = slow clock
        TestSDConfig(0, `Msg_Arg_SDConfig_ClkSrc_Speed_Slow, 0, 1); // Reset SDController's `init` state machine
        // <-- Turn on power to SD card
        TestSDConfig(0, `Msg_Arg_SDConfig_ClkSrc_Speed_Slow, 1, 0); // Trigger SDController init state machine
        
        // Wait for SD init to be complete
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            // Request SD status
            SendMsg(`Msg_Type_SDGetStatus, 0);
            // We're done when the `InitDone` bit is set
            done = spi_resp[`Resp_Arg_SDGetStatus_InitDone_Bits];
        end
        
        $display("[Testbench] Init done ✅");
    end endtask
    
    task TestSDCMD0; begin
        // ====================
        // Test SD CMD0 (GO_IDLE)
        // ====================
        $display("\n[Testbench] ========== TestSDCMD0 ==========");
        SendSDCmdResp(CMD0, `Msg_Arg_SDSendCmd_RespType_None, `Msg_Arg_SDSendCmd_DatInType_None, 0);
    end endtask
    
    task TestSDCMD8; begin
        // ====================
        // Test SD CMD8 (SEND_IF_COND)
        // ====================
        reg[`Resp_Arg_SDGetStatus_Resp_Len-1:0] sdResp;
        
        $display("\n[Testbench] ========== TestSDCMD8 ==========");
        
        // Send SD CMD8
        SendSDCmdResp(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'h000001AA);
        if (spi_resp[`Resp_Arg_SDGetStatus_RespCRCErr_Bits] !== 1'b0) begin
            $display("[Testbench] CRC error ❌");
            `Finish;
        end

        sdResp = spi_resp[`Resp_Arg_SDGetStatus_Resp_Bits];
        if (sdResp[15:8] !== 8'hAA) begin
            $display("[Testbench] Bad response: %h ❌", spi_resp);
            `Finish;
        end
    end endtask
    
    // task TestSDDatOut; begin
    //     // ====================
    //     // Test writing data to SD card / DatOut
    //     // ====================
    //     
    //     $display("\n========== TestSDDatOut ==========");
    //     
    //     // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
    //     SendSDCmdResp(CMD55, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
    //     SendSDCmdResp(ACMD23, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b1);
    //
    //     // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
    //     SendSDCmdResp(CMD25, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
    //
    //     // Clock out data on DAT lines
    //     SendMsg(`Msg_Type_PixReadout, 0);
    //
    //     // Wait until we're done clocking out data on DAT lines
    //     $display("[Testbench] Waiting while data is written...");
    //     do begin
    //         // Request SD status
    //         SendMsg(`Msg_Type_SDGetStatus, 0);
    //     end while(!resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits]);
    //     $display("[Testbench] Done writing (SD resp: %b)", resp[`Resp_Arg_SDGetStatus_Resp_Bits]);
    //
    //     // Check CRC status
    //     if (resp[`Resp_Arg_SDGetStatus_DatOutCRCErr_Bits] === 1'b0) begin
    //         $display("[Testbench] DatOut CRC OK ✅");
    //     end else begin
    //         $display("[Testbench] DatOut CRC bad ❌");
    //         `Finish;
    //     end
    //
    //     // Stop transmission
    //     SendSDCmdResp(CMD12, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 32'b0);
    // end endtask

    task TestSDDatIn; begin
        // ====================
        // Test CMD6 (SWITCH_FUNC) + DatIn
        // ====================
        
        $display("\n[Testbench] ========== TestSDDatIn ==========");
        
        // Send SD command CMD6 (SWITCH_FUNC)
        SendSDCmdResp(CMD6, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 32'h80FFFFF3);
        $display("[Testbench] Waiting for DatIn to complete...");
        do begin
            // Request SD status
            SendMsg(`Msg_Type_SDGetStatus, 0);
        end while(!spi_resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
        $display("[Testbench] DatIn completed");

        // Check DatIn CRC status
        if (spi_resp[`Resp_Arg_SDGetStatus_DatInCRCErr_Bits] === 1'b0) begin
            $display("[Testbench] DatIn CRC OK ✅");
        end else begin
            $display("[Testbench] DatIn CRC bad ❌");
            `Finish;
        end
        
        // Check the access mode from the CMD6 response
        if (spi_resp[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits] === 4'h3) begin
            $display("[Testbench] CMD6 access mode == 0x3 ✅");
        end else begin
            $display("[Testbench] CMD6 access mode == 0x%h ❌", spi_resp[`Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits]);
            `Finish;
        end
    end endtask
    
    task TestSDCMD2; begin
        // ====================
        // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
        //   Note: we expect CRC errors in the response because the R2
        //   response CRC doesn't follow the semantics of other responses
        // ====================
        
        $display("\n[Testbench] ========== TestSDCMD2 ==========");
        
        // Send SD command CMD2 (ALL_SEND_CID)
        SendSDCmdResp(CMD2, `Msg_Arg_SDSendCmd_RespType_136, `Msg_Arg_SDSendCmd_DatInType_None, 0);
        $display("[Testbench] ====================================================");
        $display("[Testbench] ^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        $display("[Testbench] ====================================================");
    end endtask
    
    task TestSDRespRecovery; begin
        reg done;
        reg[15:0] i;
        
        $display("\n[Testbench] ========== TestSDRespRecovery ==========");
        
        // Send an SD command that doesn't provide a response
        SendSDCmd(CMD0, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_None, 0);
        $display("[Testbench] Verifying that Resp times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsg(`Msg_Type_SDGetStatus, 0);
            $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                spi_resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
                spi_resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
                spi_resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
                spi_resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
            
            done = spi_resp[`Resp_Arg_SDGetStatus_RespDone_Bits];
        end
        
        if (!done) begin
            $display("[Testbench] Resp timeout ✅");
            $display("[Testbench] Testing Resp after timeout...");
            TestSDCMD8();
            $display("[Testbench] Resp Recovered ✅");
        
        end else begin
            $display("[Testbench] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask

    // task TestSDDatOutRecovery; begin
    //     reg done;
    //     reg[15:0] i;
    //
    //     // Clock out data on DAT lines, but without the SD card
    //     // expecting data so that we don't get a response
    //     SendMsg(`Msg_Type_PixReadout, 0);
    //
    //     #50000;
    //
    //     // Verify that we timeout
    //     $display("[Testbench] Verifying that DatOut times out...");
    //     done = 0;
    //     for (i=0; i<10 && !done; i++) begin
    //         SendMsg(`Msg_Type_SDGetStatus, 0);
    //         $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
    //             i+1,
    //             spi_resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
    //             spi_resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
    //             spi_resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
    //             spi_resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);
    //
    //         done = spi_resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits];
    //     end
    //
    //     if (!done) begin
    //         $display("[Testbench] DatOut timeout ✅");
    //         $display("[Testbench] Testing DatOut after timeout...");
    //         TestSDDatOut();
    //         $display("[Testbench] DatOut Recovered ✅");
    //
    //     end else begin
    //         $display("[Testbench] DatOut didn't timeout? ❌");
    //         `Finish;
    //     end
    // end endtask

    task TestSDDatInRecovery; begin
        reg done;
        reg[15:0] i;
        
        $display("\n[Testbench] ========== TestSDDatInRecovery ==========");
        
        // Send SD command that doesn't respond on the DAT lines,
        // but specify that we expect DAT data
        SendSDCmd(CMD8, `Msg_Arg_SDSendCmd_RespType_48, `Msg_Arg_SDSendCmd_DatInType_512, 0);
        $display("[Testbench] Verifying that DatIn times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsg(`Msg_Type_SDGetStatus, 0);
            $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                spi_resp[`Resp_Arg_SDGetStatus_CmdDone_Bits],
                spi_resp[`Resp_Arg_SDGetStatus_RespDone_Bits],
                spi_resp[`Resp_Arg_SDGetStatus_DatOutDone_Bits],
                spi_resp[`Resp_Arg_SDGetStatus_DatInDone_Bits]);

            done = spi_resp[`Resp_Arg_SDGetStatus_DatInDone_Bits];
        end

        if (!done) begin
            $display("[Testbench] DatIn timeout ✅");
            $display("[Testbench] Testing DatIn after timeout...");
            TestSDDatIn();
            $display("[Testbench] DatIn Recovered ✅");

        end else begin
            $display("[Testbench] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    initial begin
        // Set our initial state
        spi_dataOutReg = ~0;
        spi_dataOutEn = 0;
        
        // Pulse the clock to get SB_IO initialized
        ice_msp_spi_clk = 1;
        #1;
        ice_msp_spi_clk = 0;
        
        TestRst();
        TestNoOp();
        TestEcho(56'hCAFEBABEFEEDAA);
        TestLEDSet(4'b1010);
        TestLEDSet(4'b0101);
        TestEcho(56'h123456789ABCDE);
        TestNoOp();
        TestRst();
        
        TestSDInit();
        
        TestSDCMD0();
        TestSDCMD8();
        // TestSDDatOut();
        TestSDCMD2();
        TestSDDatIn();
        TestSDRespRecovery();
        // TestSDDatOutRecovery();
        TestSDDatInRecovery();
        
        `Finish;
    end
endmodule
`endif
