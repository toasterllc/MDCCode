`ifndef ICEAppSim_v
`define ICEAppSim_v

`include "ICEAppTypes.v"
`include "EndianSwap.v"
`include "Util.v"
`include "WordValidator.v"
`include "SDController.v"

`ifdef _ICEApp_SD_En
`include "SDCardSim.v"
`endif // _ICEApp_SD_En

`ifdef _ICEApp_Img_En
`include "ImgSim.v"
`include "ImgI2CSlaveSim.v"

// MOBILE_SDR_INIT_VAL: Initialize the memory because ImgController reads a few words
// beyond the image that's written to the RAM, and we don't want to read `x` (don't care)
// when that happens
`define MOBILE_SDR_INIT_VAL 16'hCAFE
`include "mt48h32m16lf/mobile_sdr.v"
`endif // _ICEApp_Img_En

`timescale 1ns/1ps

module ICEAppSim();
    reg         ice_img_clk16mhz = 0;
    
    reg         ice_msp_spi_clk = 0;
    wire        ice_msp_spi_data;
    
    reg         ice_st_spi_clk = 0;
    reg         ice_st_spi_cs_ = 1;
    wire[7:0]   ice_st_spi_d;
    wire        ice_st_spi_d_ready;
    wire        ice_st_spi_d_ready_rev4bodge;
    
    wire        sd_clk;
    wire        sd_cmd;
    tri1[3:0]   sd_dat;
    
    wire        img_dclk;
    wire[11:0]  img_d;
    wire        img_fv;
    wire        img_lv;
    wire        img_rst_;
    wire        img_sclk;
    tri1        img_sdata;
    
    wire        ram_clk;
    wire        ram_cke;
    wire[1:0]   ram_ba;
    wire[11:0]  ram_a;
    wire        ram_cs_;
    wire        ram_ras_;
    wire        ram_cas_;
    wire        ram_we_;
    wire[1:0]   ram_dqm;
    wire[15:0]  ram_dq;
    
    wire[3:0] ice_led;
    wire sim_spiRst_;
    
    EndianSwap #(.Width(16)) LittleFromHost16();
    EndianSwap #(.Width(32)) LittleFromHost32();
    EndianSwap #(.Width(16)) HostFromLittle16();
    EndianSwap #(.Width(32)) HostFromLittle32();
    
    // localparam Sim_ImgWidth             = 64;
    // localparam Sim_ImgHeight            = 32;
    // localparam Sim_ImgWidth             = 1006;
    // localparam Sim_ImgHeight            = 1;
    // localparam Sim_ImgPixelCount        = ImgWidth*ImgHeight;
    localparam Sim_ImgWordInitialValue  = 16'h0FFF;
    localparam Sim_ImgWordDelta         = -1;
    
    `ifdef _ICEApp_Img_En
        mobile_sdr mobile_sdr(
            .clk(ram_clk),
            .cke(ram_cke),
            .addr(ram_a),
            .ba(ram_ba),
            .cs_n(ram_cs_),
            .ras_n(ram_ras_),
            .cas_n(ram_cas_),
            .we_n(ram_we_),
            .dq(ram_dq),
            .dqm(ram_dqm)
        );
        
        ImgSim #(
            .ImgWidth(`Img_Width),
            .ImgHeight(`Img_Height)
        ) ImgSim (
            .img_dclk(img_dclk),
            .img_d(img_d),
            .img_fv(img_fv),
            .img_lv(img_lv),
            .img_rst_(img_rst_)
        );
        
        ImgI2CSlaveSim ImgI2CSlaveSim(
            .i2c_clk(img_sclk),
            .i2c_data(img_sdata)
        );
    `endif // _ICEApp_Img_En
    
    `ifdef _ICEApp_SD_En
        SDCardSim #(
            .RecvHeaderWordCount(`Img_HeaderWordCount),
            .RecvBodyWordCount(`Img_PixelCount),
            .RecvBodyWordInitialValue(Sim_ImgWordInitialValue),
            .RecvBodyWordDelta(Sim_ImgWordDelta),
            .RecvValidateChecksum(1)
        ) SDCardSim (
            .sd_clk(sd_clk),
            .sd_cmd(sd_cmd),
            .sd_dat(sd_dat)
        );
    `endif // _ICEApp_SD_En
    
    WordValidator WordValidator();
    
    Top Top(.*);
    
    initial begin
        forever begin
            ice_img_clk16mhz = ~ice_img_clk16mhz;
            #32;
        end
    end
    
    initial begin
        $dumpfile("Top.vcd");
        $dumpvars(0, ICEAppSim);
    end
    
    task TestNop; begin
        $display("\n[ICEAppSim] ========== TestNop ==========");
        SendMsg(`Msg_Type_Nop, 56'h00000000000000);
    end endtask
    
    task TestEcho(input[`Msg_Arg_Echo_Msg_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[ICEAppSim] ========== TestEcho ==========");
        arg[`Msg_Arg_Echo_Msg_Bits] = val;
        
        SendMsg(`Msg_Type_Echo, arg);
        if (spi_resp[`Resp_Arg_Echo_Msg_Bits] === val) begin
            $display("[ICEAppSim] Response OK: %h ✅", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
        end else begin
            $display("[ICEAppSim] Bad response: %h ❌", spi_resp[`Resp_Arg_Echo_Msg_Bits]);
            `Finish;
        end
    end endtask
    
    task TestLEDSet(input[`Msg_Arg_LEDSet_Val_Len-1:0] val); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[ICEAppSim] ========== TestLEDSet ==========");
        arg = 0;
        arg[`Msg_Arg_LEDSet_Val_Bits] = val;
        
        SendMsg(`Msg_Type_LEDSet, arg);
        if (ice_led === val) begin
            $display("[ICEAppSim] ice_led matches (%b) ✅", ice_led);
        end else begin
            $display("[ICEAppSim] ice_led doesn't match (expected: %b, got: %b) ❌", val, ice_led);
            `Finish;
        end
    end endtask
    
    task TestImgReset; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n========== TestImgReset ==========");
        
        // ====================
        // Test Img reset
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgReset_Val_Bits] = 0;
        SendMsg(`Msg_Type_ImgReset, arg);
        if (img_rst_ === arg[`Msg_Arg_ImgReset_Val_Bits]) begin
            $display("[ICEAppSim] Reset=0 success ✅");
        end else begin
            $display("[ICEAppSim] Reset=0 failed ❌");
            `Finish;
        end
        
        arg = 0;
        arg[`Msg_Arg_ImgReset_Val_Bits] = 1;
        SendMsg(`Msg_Type_ImgReset, arg);
        if (img_rst_ === arg[`Msg_Arg_ImgReset_Val_Bits]) begin
            $display("[ICEAppSim] Reset=1 success ✅");
        end else begin
            $display("[ICEAppSim] Reset=1 failed ❌");
            `Finish;
        end
    end endtask
    
    task TestImgI2CWriteRead; begin
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;
        
        $display("\n[ICEAppSim] ========== TestImgI2CWriteRead ==========");
        
        // ====================
        // Test ImgI2C Write (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 1;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_2;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h4242;
        arg[`Msg_Arg_ImgI2CTransaction_WriteData_Bits] = 16'hCAFE;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[ICEAppSim] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[ICEAppSim] Write success ✅");
        end else begin
            $display("[ICEAppSim] Write failed ❌");
            `Finish;
        end
        
        // ====================
        // Test ImgI2C Read (len=2)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_2;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h4242;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[ICEAppSim] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[ICEAppSim] Read success ✅");
        end else begin
            $display("[ICEAppSim] Read failed ❌");
            `Finish;
        end
        
        if (spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits] === 16'hCAFE) begin
            $display("[ICEAppSim] Read correct data ✅ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
        end else begin
            $display("[ICEAppSim] Read incorrect data ❌ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
            `Finish;
        end
        
        // ====================
        // Test ImgI2C Write (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 1;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_1;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h8484;
        arg[`Msg_Arg_ImgI2CTransaction_WriteData_Bits] = 16'h0037;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[ICEAppSim] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[ICEAppSim] Write success ✅");
        end else begin
            $display("[ICEAppSim] Write failed ❌");
            `Finish;
        end
        
        // ====================
        // Test ImgI2C Read (len=1)
        // ====================
        arg = 0;
        arg[`Msg_Arg_ImgI2CTransaction_Write_Bits] = 0;
        arg[`Msg_Arg_ImgI2CTransaction_DataLen_Bits] = `Msg_Arg_ImgI2CTransaction_DataLen_1;
        arg[`Msg_Arg_ImgI2CTransaction_RegAddr_Bits] = 16'h8484;
        SendMsg(`Msg_Type_ImgI2CTransaction, arg);
        
        done = 0;
        while (!done) begin
            SendMsg(`Msg_Type_ImgI2CStatus, 0);
            $display("[ICEAppSim] ImgI2C status: done:%b err:%b readData:0x%x",
                spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
                spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
            );
            
            done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
        end
        
        if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
            $display("[ICEAppSim] Read success ✅");
        end else begin
            $display("[ICEAppSim] Read failed ❌");
            `Finish;
        end
        
        if ((spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF) === 16'h0037) begin
            $display("[ICEAppSim] Read correct data ✅ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
        end else begin
            $display("[ICEAppSim] Read incorrect data ❌ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
            `Finish;
        end
    end endtask
    
    task TestImgSetHeader(input[`Msg_Arg_ImgSetHeader_Idx_Len-1:0] idx, input[`Msg_Arg_ImgSetHeader_Header_Len-1:0] header); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        $display("\n[ICEAppSim] ========== TestImgSetHeader (idx:%0d, header:%h) ==========", idx, header);
        
        arg = 0;
        arg[`Msg_Arg_ImgSetHeader_Idx_Bits]     = idx;
        arg[`Msg_Arg_ImgSetHeader_Header_Bits]  = header;
        
        SendMsg(`Msg_Type_ImgSetHeader, arg);
    end endtask
    
    task TestImgCapture; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n[ICEAppSim] ========== TestImgCapture ==========");
        
        arg = 0;
        arg[`Msg_Arg_ImgCapture_DstBlock_Bits] = 0;
        arg[`Msg_Arg_ImgCapture_SkipCount_Bits] = 1;
        SendMsg(`Msg_Type_ImgCapture, arg);
        
        // Wait until capture is done
        $display("[ICEAppSim] Waiting until capture is complete...");
        do begin
            // Request Img status
            SendMsg(`Msg_Type_ImgCaptureStatus, 0);
        end while(!spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits]);
        $display("[ICEAppSim] Capture done ✅ (done:%b image size:%0d, highlightCount:%0d, shadowCount:%0d)",
            spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_WordCount_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits],
            spi_resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits],
        );
    end endtask
    
    task TestImgReadout; begin
        reg[`Msg_Arg_Len-1:0] arg;
        $display("\n[ICEAppSim] ========== TestImgReadout ==========");
        
        arg = 0;
        SendMsg(`Msg_Type_ImgReadout, arg);
    end endtask
    
    localparam CMD0     = 6'd0;     // GO_IDLE_STATE
    localparam CMD2     = 6'd2;     // ALL_SEND_BIT_CID
    localparam CMD3     = 6'd3;     // SEND_BIT_RELATIVE_ADDR
    localparam CMD6     = 6'd6;     // SWITCH_FUNC
    localparam CMD7     = 6'd7;     // SELECT_CARD/DESELECT_CARD
    localparam CMD8     = 6'd8;     // SEND_BIT_IF_COND
    localparam CMD11    = 6'd11;    // VOLTAGE_SWITCH
    localparam CMD12    = 6'd12;    // STOP_TRANSMISSION
    localparam CMD18    = 6'd18;    // READ_MULTIPLE_BLOCK
    localparam CMD25    = 6'd25;    // WRITE_MULTIPLE_BLOCK
    localparam CMD41    = 6'd41;    // SD_SEND_BIT_OP_COND
    localparam CMD55    = 6'd55;    // APP_CMD
    localparam ACMD23    = 6'd23;   // SET_WR_BLK_ERASE_COUNT
    
    task SendSDCmd(
        input[5:0] sdCmd,
        input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType,
        input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType,
        input[31:0] sdArg
    ); begin
        
        reg[`Msg_Arg_Len-1] arg;
        arg = 0;
        arg[`Msg_Arg_SDSendCmd_RespType_Bits] = respType;
        arg[`Msg_Arg_SDSendCmd_DatInType_Bits] = datInType;
        arg[`Msg_Arg_SDSendCmd_CmdData_Bits] = {2'b01, sdCmd, sdArg, 7'b0, 1'b1};
        
        SendMsg(`Msg_Type_SDSendCmd, arg);
    end endtask
    
    task SendSDCmdResp(
        input[5:0] sdCmd,
        input[`Msg_Arg_SDSendCmd_RespType_Len-1:0] respType,
        input[`Msg_Arg_SDSendCmd_DatInType_Len-1:0] datInType,
        input[31:0] sdArg
    ); begin
        
        reg[15:0] i;
        reg done;
        SendSDCmd(sdCmd, respType, datInType, sdArg);
        
        // Wait for SD command to be sent
        done = 0;
        for (i=0; i<100 && !done; i++) begin
            // Request SD status
            SendMsg(`Msg_Type_SDStatus, 0);
            // We're done when the SD command is sent
            done = spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits];
            // If a response is expected, we're done when the response is received
            if (respType !== `SDController_RespType_None) done &= spi_resp[`Resp_Arg_SDStatus_RespDone_Bits];
            if (datInType === `SDController_DatInType_512x1) done &= spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits];
            
            // Our clock is much faster than the SD slow clock (64 MHz vs .4 MHz),
            // so wait a bit before asking for the status again
            #(50_000);
        end
        
        if (!done) begin
            $display("[ICEAppSim] SD card response timeout ❌");
            `Finish;
        end
    end endtask
    
    task TestSDConfig(
        input[`Msg_Arg_SDInit_Clk_Delay_Len-1:0] delay,
        input[`Msg_Arg_SDInit_Clk_Speed_Len-1:0] speed,
        input[`Msg_Arg_SDInit_Trigger_Len-1:0] trigger,
        input[`Msg_Arg_SDInit_Reset_Len-1:0] reset
    ); begin
        reg[`Msg_Arg_Len-1:0] arg;
        
        // $display("\n[ICEAppSim] ========== TestSDConfig ==========");
        arg[`Msg_Arg_SDInit_Clk_Delay_Bits] = delay;
        arg[`Msg_Arg_SDInit_Clk_Speed_Bits] = speed;
        arg[`Msg_Arg_SDInit_Trigger_Bits] = trigger;
        arg[`Msg_Arg_SDInit_Reset_Bits] = reset;
        
        SendMsg(`Msg_Type_SDInit, arg);
    end endtask
    
    task TestSDInit; begin
        reg[15:0] i;
        reg[`Msg_Arg_Len-1:0] arg;
        reg done;
        
        $display("\n[ICEAppSim] ========== TestSDInit ==========");
        
        //           delay, speed,                            trigger, reset
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
        #((10*1e9)/400e3); // Wait 10 400kHz cycles
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 0,       0);
        #((10*1e9)/400e3); // Wait 10 400kHz cycles
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 0,       1);
        #((10*1e9)/400e3); // Wait 10 400kHz cycles
        // <-- Turn on power to SD card
        TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 1,       0);
    
    `ifdef SIM
        // Wait 50us, because waiting 5ms takes forever in simulation
        $display("[ICEAppSim] Waiting 50us (and pretending it's 5ms)...");
        #(50_000);
    `else
        // Wait 5ms
        $display("[ICEAppSim] Waiting 5ms...");
        #(5_000_000);
    `endif
        $display("[ICEAppSim] 5ms elapsed");
        
        // // Wait for SD init to be complete
        // done = 0;
        // for (i=0; i<10 && !done; i++) begin
        //     // Request SD status
        //     SendMsg(`Msg_Type_SDStatus, 0);
        //     // We're done when the `InitDone` bit is set
        //     done = spi_resp[`Resp_Arg_SDStatus_InitDone_Bits];
        // end
        
        $display("[ICEAppSim] Init done ✅");
    end endtask
    
    task TestSDCMD0; begin
        // ====================
        // Test SD CMD0 (GO_IDLE)
        // ====================
        $display("\n[ICEAppSim] ========== TestSDCMD0 ==========");
        SendSDCmdResp(CMD0, `SDController_RespType_None, `SDController_DatInType_None, 0);
    end endtask
    
    task TestSDCMD2; begin
        // ====================
        // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
        //   Note: we expect CRC errors in the response because the R2
        //   response CRC doesn't follow the semantics of other responses
        // ====================
        
        $display("\n[ICEAppSim] ========== TestSDCMD2 ==========");
        
        // Send SD command CMD2 (ALL_SEND_CID)
        SendSDCmdResp(CMD2, `SDController_RespType_136, `SDController_DatInType_None, 0);
        $display("[ICEAppSim] ====================================================");
        $display("[ICEAppSim] ^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
        $display("[ICEAppSim] ====================================================");
    end endtask
    
    task TestSDCMD6; begin
        // ====================
        // Test CMD6 (SWITCH_FUNC) + DatIn
        // ====================
        
        $display("\n[ICEAppSim] ========== TestSDCMD6 ==========");
        
        // Send SD command CMD6 (SWITCH_FUNC)
        SendSDCmdResp(CMD6, `SDController_RespType_48, `SDController_DatInType_512x1, 32'h80FFFFF3);
        
        // Check DatIn CRC status
        if (spi_resp[`Resp_Arg_SDStatus_DatInCRCErr_Bits] === 1'b0) begin
            $display("[ICEAppSim] DatIn CRC OK ✅");
        end else begin
            $display("[ICEAppSim] DatIn CRC bad ❌");
            `Finish;
        end
        
        TestSDCMD6_CheckAccessMode(); // Provided by client
    end endtask
    
    task TestSDCMD8; begin
        // ====================
        // Test SD CMD8 (SEND_IF_COND)
        // ====================
        reg[`Resp_Arg_SDStatus_Resp_Len-1:0] sdResp;
        
        $display("\n[ICEAppSim] ========== TestSDCMD8 ==========");
        
        // Send SD CMD8
        SendSDCmdResp(CMD8, `SDController_RespType_48, `SDController_DatInType_None, 32'h000001AA);
        if (spi_resp[`Resp_Arg_SDStatus_RespCRCErr_Bits] !== 1'b0) begin
            $display("[ICEAppSim] CRC error ❌");
            `Finish;
        end
        
        sdResp = spi_resp[`Resp_Arg_SDStatus_Resp_Bits];
        if (sdResp[15:8] !== 8'hAA) begin
            $display("[ICEAppSim] Bad response: %h ❌", spi_resp);
            `Finish;
        end
    end endtask
    
    task TestSDRespRecovery; begin
        reg done;
        reg[15:0] i;
        
        $display("\n[ICEAppSim] ========== TestSDRespRecovery ==========");
        
        // Send an SD command that doesn't provide a response
        SendSDCmd(CMD0, `SDController_RespType_48, `SDController_DatInType_None, 0);
        $display("[ICEAppSim] Verifying that Resp times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsg(`Msg_Type_SDStatus, 0);
            $display("[ICEAppSim] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);
            
            done = spi_resp[`Resp_Arg_SDStatus_RespDone_Bits];
        end
        
        if (!done) begin
            $display("[ICEAppSim] Resp timeout ✅");
            $display("[ICEAppSim] Testing Resp after timeout...");
            TestSDCMD8();
            $display("[ICEAppSim] Resp Recovered ✅");
        
        end else begin
            $display("[ICEAppSim] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    task TestImgReadoutToSD; begin
        // ====================
        // Test writing data to SD card / DatOut
        // ====================
        
        $display("\n========== TestImgReadoutToSD ==========");
        
        // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
        SendSDCmdResp(CMD55, `SDController_RespType_48, `SDController_DatInType_None, 32'b0);
        SendSDCmdResp(ACMD23, `SDController_RespType_48, `SDController_DatInType_None, 32'b1);
        
        // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
        SendSDCmdResp(CMD25, `SDController_RespType_48, `SDController_DatInType_None, 32'b0);
        
        // Start image readout
        TestImgReadout();
        
        // Wait until we're done clocking out data on DAT lines
        $display("[ICEAppSim] Waiting while data is written...");
        do begin
            // Request SD status
            SendMsg(`Msg_Type_SDStatus, 0);
        end while(!spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits]);
        $display("[ICEAppSim] Done writing (SD resp: %b)", spi_resp[`Resp_Arg_SDStatus_Resp_Bits]);
        
        // Check CRC status
        if (spi_resp[`Resp_Arg_SDStatus_DatOutCRCErr_Bits] === 1'b0) begin
            $display("[ICEAppSim] DatOut CRC OK ✅");
        end else begin
            $display("[ICEAppSim] DatOut CRC bad ❌");
            `Finish;
        end
        
        // Stop transmission
        SendSDCmdResp(CMD12, `SDController_RespType_48, `SDController_DatInType_None, 32'b0);
    end endtask
    
    task TestImgReadoutToSDRecovery; begin
        reg done;
        reg[15:0] i;
        
        $display("\n========== TestImgReadoutToSDRecovery ==========");
        
        // Clock out data on DAT lines, but without the SD card
        // expecting data so that we don't get a response
        TestImgReadout();
        
        #50000;
        
        // Verify that we timeout
        $display("[ICEAppSim] Verifying that DatOut times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsg(`Msg_Type_SDStatus, 0);
            $display("[ICEAppSim] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);
            
            done = spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits];
        end
        
        if (!done) begin
            $display("[ICEAppSim] DatOut timeout ✅");
            $display("[ICEAppSim] Testing DatOut after timeout...");
            TestImgReadoutToSD();
            $display("[ICEAppSim] DatOut Recovered ✅");
            
        end else begin
            $display("[ICEAppSim] DatOut didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    task TestSDReadoutToSPI; begin
        $display("\n[ICEAppSim] ========== TestSDReadoutToSPI ==========");
        
        // Send SD command CMD18 (READ_MULTIPLE_BLOCK)
        SendSDCmdResp(CMD18, `SDController_RespType_48, `SDController_DatInType_4096xN, 32'b0);
        
        TestSDReadoutToSPI_Readout();
        
        // Stop transmission
        SendSDCmdResp(CMD12, `SDController_RespType_48, `SDController_DatInType_None, 32'b0);
    end endtask
    
    task TestSDReadoutToSPIRecovery; begin
        reg done;
        reg[15:0] i;
        
        $display("\n[ICEAppSim] ========== TestSDReadoutToSPIRecovery ==========");
        
        // Send SD command that doesn't respond on the DAT lines,
        // but specify that we expect DAT data
        SendSDCmd(CMD8, `SDController_RespType_48, `SDController_DatInType_512x1, 0);
        $display("[ICEAppSim] Verifying that DatIn times out...");
        done = 0;
        for (i=0; i<10 && !done; i++) begin
            SendMsg(`Msg_Type_SDStatus, 0);
            $display("[ICEAppSim] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
                i+1,
                spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
                spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);
            
            done = spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits];
        end
        
        if (!done) begin
            $display("[ICEAppSim] DatIn timeout ✅");
            $display("[ICEAppSim] Testing DatIn after timeout...");
            TestSDCMD6();
            $display("[ICEAppSim] DatIn Recovered ✅");
        
        end else begin
            $display("[ICEAppSim] DatIn didn't timeout? ❌");
            `Finish;
        end
    end endtask
    
    task TestImgReadoutToSPI; begin
        $display("\n[ICEAppSim] ========== TestImgReadoutToSPI ==========");
        TestImgReadout();
        TestImgReadoutToSPI_Readout();
    end endtask
    
`ifdef ICEApp_MSP_En
    `include "ICEAppMSPSim.v"
`endif // ICEApp_MSP_En
    
`ifdef ICEApp_STM_En
    `include "ICEAppSTMSim.v"
`endif // ICEApp_STM_En
    
    initial begin
        TestRst();
        TestEcho(56'h00000000000000);
        TestEcho(56'h00000000000000);
        TestEcho(56'hCAFEBABEFEEDAA);
        TestNop();
        TestEcho(56'hCAFEBABEFEEDAA);
        TestEcho(56'h123456789ABCDE);
        TestLEDSet(4'b1010);
        TestLEDSet(4'b0101);
        TestEcho(56'h123456789ABCDE);
        TestNop();
        TestRst();
        
        `ifdef _ICEApp_Img_En
            // Do Img stuff before SD stuff, so that an image is ready for readout to the SD card
            TestImgReset();
            TestImgSetHeader(0, {
                LittleFromHost16.Swap(16'h4242)     /* version          */,
                LittleFromHost16.Swap(16'd2304)     /* image width      */,
                LittleFromHost16.Swap(16'd1296)     /* image height     */
            });
            
            TestImgSetHeader(1, {
                LittleFromHost32.Swap(32'hCAFEBABE) /* counter          */,
                LittleFromHost16.Swap(16'b0)        /* padding          */
            });
            
            TestImgSetHeader(2, {
                LittleFromHost32.Swap(32'hDEADBEEF) /* timestamp        */,
                LittleFromHost16.Swap(16'b0)        /* padding          */
            });
            
            TestImgSetHeader(3, {
                LittleFromHost16.Swap(16'h1111)     /* coarse int time  */,
                LittleFromHost16.Swap(16'h2222)     /* analog gain      */,
                LittleFromHost16.Swap(16'b0)        /* padding          */
            });
            
            TestImgI2CWriteRead();
            TestImgCapture();
        `endif // _ICEApp_Img_En
        
        `ifdef _ICEApp_SD_En
            TestSDInit();
            TestSDCMD0();
            TestSDCMD8();
            TestSDCMD2();
            TestSDCMD6();
            //           delay, speed,                            trigger, reset
            TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
            TestSDConfig(0,     `SDController_Init_ClkSpeed_Fast, 0,       0);
            
            TestSDRespRecovery();
        `endif // _ICEApp_SD_En
        
        `ifdef ICEApp_ImgReadoutToSD_En
            TestImgReadoutToSD();
            TestImgReadoutToSDRecovery();
        `endif // ICEApp_ImgReadoutToSD_En
        
        `ifdef ICEApp_SDReadoutToSPI_En
            TestSDReadoutToSPI();
            TestLEDSet(4'b1010);
            TestSDReadoutToSPI();
        `endif // ICEApp_SDReadoutToSPI_En

        `ifdef ICEApp_ImgReadoutToSPI_En
            TestImgReadoutToSPI();
        `endif // ICEApp_ImgReadoutToSPI_En
        
        `Finish;
    end
    
endmodule

`endif // ICEAppSim
