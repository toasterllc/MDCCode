`ifndef ICEAppTest_v
`define ICEAppTest_v

task TestNop; begin
    $display("\n[Testbench] ========== TestNop ==========");
    SendMsg(`Msg_Type_Nop, 56'h00000000000000);
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
    arg = 0;
    arg[`Msg_Arg_LEDSet_Val_Bits] = val;
    
    SendMsg(`Msg_Type_LEDSet, arg);
    if (ice_led === val) begin
        $display("[Testbench] ice_led matches (%b) ✅", ice_led);
    end else begin
        $display("[Testbench] ice_led doesn't match (expected: %b, got: %b) ❌", val, ice_led);
        `Finish;
    end
end endtask










task TestImgI2CWriteRead; begin
    reg[`Msg_Arg_Len-1:0] arg;
    reg done;
    
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
        $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
            spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
        );

        done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
    end

    if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
        $display("[Testbench] Write success ✅");
    end else begin
        $display("[Testbench] Write failed ❌");
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
        $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
            spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
        );
        
        done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
    end
    
    if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
        $display("[Testbench] Read success ✅");
    end else begin
        $display("[Testbench] Read failed ❌");
        `Finish;
    end
    
    if (spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits] === 16'hCAFE) begin
        $display("[Testbench] Read correct data ✅ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
    end else begin
        $display("[Testbench] Read incorrect data ❌ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]);
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
        $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
            spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
        );
        
        done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
    end
    
    if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
        $display("[Testbench] Write success ✅");
    end else begin
        $display("[Testbench] Write failed ❌");
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
        $display("[Testbench] ImgI2C status: done:%b err:%b readData:0x%x",
            spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits],
            spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]
        );
        
        done = spi_resp[`Resp_Arg_ImgI2CStatus_Done_Bits];
    end

    if (!spi_resp[`Resp_Arg_ImgI2CStatus_Err_Bits]) begin
        $display("[Testbench] Read success ✅");
    end else begin
        $display("[Testbench] Read failed ❌");
        `Finish;
    end
    
    if ((spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF) === 16'h0037) begin
        $display("[Testbench] Read correct data ✅ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
    end else begin
        $display("[Testbench] Read incorrect data ❌ (0x%x)", spi_resp[`Resp_Arg_ImgI2CStatus_ReadData_Bits]&16'h00FF);
        `Finish;
    end
end endtask

task TestImgSetHeader1(input[7:0] version, input[31:0] timestamp, input[15:0] imageWidth); begin
    reg[`Msg_Arg_Len-1:0] arg;
    
    $display("\n[Testbench] ========== TestImgSetHeader1 ==========");
    arg = 0;
    arg[55:48] = version;
    arg[47:16] = timestamp;
    arg[15: 0] = imageWidth;
    
    SendMsg(`Msg_Type_ImgSetHeader1, arg);
end endtask

task TestImgSetHeader2(input[15:0] imageHeight, input[15:0] exposure, input[15:0] gain); begin
    reg[`Msg_Arg_Len-1:0] arg;
    
    $display("\n[Testbench] ========== TestImgSetHeader2 ==========");
    arg = 0;
    arg[55:40] = imageHeight;
    arg[39:24] = exposure;
    arg[23: 8] = gain;
    SendMsg(`Msg_Type_ImgSetHeader2, arg);
end endtask

task TestImgCapture; begin
    reg[`Msg_Arg_Len-1:0] arg;
    $display("\n[Testbench] ========== TestImgCapture ==========");
    
    arg = 0;
    arg[`Msg_Arg_ImgCapture_DstBlock_Bits] = 0;
    SendMsg(`Msg_Type_ImgCapture, arg);
    
    // Wait until capture is done
    $display("[Testbench] Waiting until capture is complete...");
    do begin
        // Request Img status
        SendMsg(`Msg_Type_ImgCaptureStatus, 0);
    end while(!spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits]);
    $display("[Testbench] Capture done ✅ (done:%b image size:%0d, highlightCount:%0d, shadowCount:%0d)",
        spi_resp[`Resp_Arg_ImgCaptureStatus_Done_Bits],
        spi_resp[`Resp_Arg_ImgCaptureStatus_WordCount_Bits],
        spi_resp[`Resp_Arg_ImgCaptureStatus_HighlightCount_Bits],
        spi_resp[`Resp_Arg_ImgCaptureStatus_ShadowCount_Bits],
    );
end endtask

task TestImgReadout; begin
    reg[`Msg_Arg_Len-1:0] arg;
    $display("\n[Testbench] ========== TestImgReadout ==========");
    
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
        $display("[Testbench] SD card response timeout ❌");
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
    
    // $display("\n[Testbench] ========== TestSDConfig ==========");
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
    
    $display("\n[Testbench] ========== TestSDInit ==========");
    
    //           delay, speed,                            trigger, reset
    TestSDConfig(0,     `SDController_Init_ClkSpeed_Off,  0,       0);
    #((10*1e9)/400e3); // Wait 10 400kHz cycles
    TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 0,       0);
    #((10*1e9)/400e3); // Wait 10 400kHz cycles
    TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 0,       1);
    #((10*1e9)/400e3); // Wait 10 400kHz cycles
    // <-- Turn on power to SD card
    TestSDConfig(0,     `SDController_Init_ClkSpeed_Slow, 1,       0);
    
`ifdef SD_LVS_SHORT_INIT
    // Wait 50us, because waiting 5ms takes forever in simulation
    $display("[Testbench] Waiting 50us (and pretending it's 5ms)...");
    #(50_000);
`else
    // Wait 5ms
    $display("[Testbench] Waiting 5ms...");
    #(5_000_000);
`endif
    $display("[Testbench] 5ms elapsed");
    
    // // Wait for SD init to be complete
    // done = 0;
    // for (i=0; i<10 && !done; i++) begin
    //     // Request SD status
    //     SendMsg(`Msg_Type_SDStatus, 0);
    //     // We're done when the `InitDone` bit is set
    //     done = spi_resp[`Resp_Arg_SDStatus_InitDone_Bits];
    // end
    
    $display("[Testbench] Init done ✅");
end endtask

task TestSDCMD0; begin
    // ====================
    // Test SD CMD0 (GO_IDLE)
    // ====================
    $display("\n[Testbench] ========== TestSDCMD0 ==========");
    SendSDCmdResp(CMD0, `SDController_RespType_None, `SDController_DatInType_None, 0);
end endtask

task TestSDCMD2; begin
    // ====================
    // Test CMD2 (ALL_SEND_CID) + long SD card response (136 bits)
    //   Note: we expect CRC errors in the response because the R2
    //   response CRC doesn't follow the semantics of other responses
    // ====================
    
    $display("\n[Testbench] ========== TestSDCMD2 ==========");
    
    // Send SD command CMD2 (ALL_SEND_CID)
    SendSDCmdResp(CMD2, `SDController_RespType_136, `SDController_DatInType_None, 0);
    $display("[Testbench] ====================================================");
    $display("[Testbench] ^^^ WE EXPECT CRC ERRORS IN THE SD CARD RESPONSE ^^^");
    $display("[Testbench] ====================================================");
end endtask

task TestSDCMD6; begin
    // ====================
    // Test CMD6 (SWITCH_FUNC) + DatIn
    // ====================
    
    $display("\n[Testbench] ========== TestSDCMD6 ==========");
    
    // Send SD command CMD6 (SWITCH_FUNC)
    SendSDCmdResp(CMD6, `SDController_RespType_48, `SDController_DatInType_512x1, 32'h80FFFFF3);
    
    // Check DatIn CRC status
    if (spi_resp[`Resp_Arg_SDStatus_DatInCRCErr_Bits] === 1'b0) begin
        $display("[Testbench] DatIn CRC OK ✅");
    end else begin
        $display("[Testbench] DatIn CRC bad ❌");
        `Finish;
    end
    
    TestSDCMD6_CheckAccessMode(); // Provided by client
end endtask

task TestSDCMD8; begin
    // ====================
    // Test SD CMD8 (SEND_IF_COND)
    // ====================
    reg[`Resp_Arg_SDStatus_Resp_Len-1:0] sdResp;
    
    $display("\n[Testbench] ========== TestSDCMD8 ==========");
    
    // Send SD CMD8
    SendSDCmdResp(CMD8, `SDController_RespType_48, `SDController_DatInType_None, 32'h000001AA);
    if (spi_resp[`Resp_Arg_SDStatus_RespCRCErr_Bits] !== 1'b0) begin
        $display("[Testbench] CRC error ❌");
        `Finish;
    end

    sdResp = spi_resp[`Resp_Arg_SDStatus_Resp_Bits];
    if (sdResp[15:8] !== 8'hAA) begin
        $display("[Testbench] Bad response: %h ❌", spi_resp);
        `Finish;
    end
end endtask

task TestSDRespRecovery; begin
    reg done;
    reg[15:0] i;
    
    $display("\n[Testbench] ========== TestSDRespRecovery ==========");
    
    // Send an SD command that doesn't provide a response
    SendSDCmd(CMD0, `SDController_RespType_48, `SDController_DatInType_None, 0);
    $display("[Testbench] Verifying that Resp times out...");
    done = 0;
    for (i=0; i<10 && !done; i++) begin
        SendMsg(`Msg_Type_SDStatus, 0);
        $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
            i+1,
            spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);
        
        done = spi_resp[`Resp_Arg_SDStatus_RespDone_Bits];
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

task TestSDDatOut; begin
    // ====================
    // Test writing data to SD card / DatOut
    // ====================
    
    $display("\n========== TestSDDatOut ==========");
    
    // Send SD command ACMD23 (SET_WR_BLK_ERASE_COUNT)
    SendSDCmdResp(CMD55, `SDController_RespType_48, `SDController_DatInType_None, 32'b0);
    SendSDCmdResp(ACMD23, `SDController_RespType_48, `SDController_DatInType_None, 32'b1);
    
    // Send SD command CMD25 (WRITE_MULTIPLE_BLOCK)
    SendSDCmdResp(CMD25, `SDController_RespType_48, `SDController_DatInType_None, 32'b0);
    
    // Clock out data on DAT lines
    TestImgReadout();
    
    // Wait until we're done clocking out data on DAT lines
    $display("[Testbench] Waiting while data is written...");
    do begin
        // Request SD status
        SendMsg(`Msg_Type_SDStatus, 0);
    end while(!spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits]);
    $display("[Testbench] Done writing (SD resp: %b)", spi_resp[`Resp_Arg_SDStatus_Resp_Bits]);
    
    // Check CRC status
    if (spi_resp[`Resp_Arg_SDStatus_DatOutCRCErr_Bits] === 1'b0) begin
        $display("[Testbench] DatOut CRC OK ✅");
    end else begin
        $display("[Testbench] DatOut CRC bad ❌");
        `Finish;
    end
    
    // Stop transmission
    SendSDCmdResp(CMD12, `SDController_RespType_48, `SDController_DatInType_None, 32'b0);
end endtask

task TestSDDatOutRecovery; begin
    reg done;
    reg[15:0] i;

    // Clock out data on DAT lines, but without the SD card
    // expecting data so that we don't get a response
    TestImgReadout();

    #50000;

    // Verify that we timeout
    $display("[Testbench] Verifying that DatOut times out...");
    done = 0;
    for (i=0; i<10 && !done; i++) begin
        SendMsg(`Msg_Type_SDStatus, 0);
        $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
            i+1,
            spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);

        done = spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits];
    end

    if (!done) begin
        $display("[Testbench] DatOut timeout ✅");
        $display("[Testbench] Testing DatOut after timeout...");
        TestSDDatOut();
        $display("[Testbench] DatOut Recovered ✅");

    end else begin
        $display("[Testbench] DatOut didn't timeout? ❌");
        `Finish;
    end
end endtask

task TestSDDatIn; begin
    $display("\n[Testbench] ========== TestSDDatIn ==========");
    
    // Send SD command CMD18 (READ_MULTIPLE_BLOCK)
    SendSDCmdResp(CMD18, `SDController_RespType_48, `SDController_DatInType_4096xN, 32'b0);
    
    TestSDDatIn_Readout();
end endtask

task TestSDDatInRecovery; begin
    reg done;
    reg[15:0] i;
    
    $display("\n[Testbench] ========== TestSDDatInRecovery ==========");
    
    // Send SD command that doesn't respond on the DAT lines,
    // but specify that we expect DAT data
    SendSDCmd(CMD8, `SDController_RespType_48, `SDController_DatInType_512x1, 0);
    $display("[Testbench] Verifying that DatIn times out...");
    done = 0;
    for (i=0; i<10 && !done; i++) begin
        SendMsg(`Msg_Type_SDStatus, 0);
        $display("[Testbench] Pre-timeout status (%0d/10): sdCmdDone:%b sdRespDone:%b sdDatOutDone:%b sdDatInDone:%b",
            i+1,
            spi_resp[`Resp_Arg_SDStatus_CmdDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_RespDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_DatOutDone_Bits],
            spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits]);

        done = spi_resp[`Resp_Arg_SDStatus_DatInDone_Bits];
    end

    if (!done) begin
        $display("[Testbench] DatIn timeout ✅");
        $display("[Testbench] Testing DatIn after timeout...");
        TestSDCMD6();
        $display("[Testbench] DatIn Recovered ✅");

    end else begin
        $display("[Testbench] DatIn didn't timeout? ❌");
        `Finish;
    end
end endtask












`endif
