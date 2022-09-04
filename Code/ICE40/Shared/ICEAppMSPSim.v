reg[`Msg_Len-1:0] spi_dataOutReg = 0;
reg[`Resp_Len-1:0] spi_resp = 0;

reg spi_dataOutEn = 0;    
wire spi_dataIn = ice_msp_spi_data;
assign ice_msp_spi_data = (spi_dataOutEn ? `LeftBit(spi_dataOutReg, 0) : 1'bz);

localparam ice_msp_spi_clk_HALF_PERIOD = 32; // 16 MHz
// localparam ice_msp_spi_clk_HALF_PERIOD = 64; // 8 MHz
// localparam ice_msp_spi_clk_HALF_PERIOD = 1024; // 1 MHz
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
    // Only do this if typ!=0. For nop's (typ==0), we don't want to perform these
    // turnaround cycles because we're no longer driving the SPI data line,
    // so the SPI state machine will (correctly) give an error (in simulation)
    // when a SPI clock is supplied but the SPI data line is invalid.
    if (typ !== 0) begin
        for (i=0; i<8; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
        end
    end
    
    // Clock in response (if one is sent for this type of message)
    if (typ[`Msg_Type_Resp_Bits]) begin
        for (i=0; i<`Resp_Len; i++) begin
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 1;
        
                spi_resp = spi_resp<<1|spi_dataIn;
        
            #(ice_msp_spi_clk_HALF_PERIOD);
            ice_msp_spi_clk = 0;
        end
    end
    
    // Give some down time to prevent the SPI state machine from resetting.
    // This can happen if the SPI master (this ICEAppSim) delivers clocks
    // at the same frequency as spirst_clk. In that case, it's possible
    // for the reset logic to always observe the SPI clock as being high
    // (even though it's toggling), and trigger a reset.
    #128;
end endtask

task TestRst; begin
    $display("\n[ICEAppSim] ========== TestRst ==========");
    
    spi_dataOutReg = 0;
    spi_dataOutEn = 1;
    
    $display("[ICEAppSim] ice_msp_spi_clk = 0");
    ice_msp_spi_clk = 0;
    #20000;
    
    if (sim_spiRst_ === 1'b1) begin
        $display("[ICEAppSim] sim_spiRst_ === 1'b1 ✅");
    end else begin
        $display("[ICEAppSim] sim_spiRst_ !== 1'b1 ❌ (%b)", sim_spiRst_);
        `Finish;
    end
    
    $display("\n[ICEAppSim] ice_msp_spi_clk = 1");
    ice_msp_spi_clk = 1;
    #20000;
    
    if (sim_spiRst_ === 1'b0) begin
        $display("[ICEAppSim] sim_spiRst_ === 1'b0 ✅");
    end else begin
        $display("[ICEAppSim] sim_spiRst_ !== 1'b0 ❌ (%b)", sim_spiRst_);
        `Finish;
    end
    
    $display("\n[ICEAppSim] ice_msp_spi_clk = 0");
    ice_msp_spi_clk = 0;
    #20000;
    
    if (sim_spiRst_ === 1'b1) begin
        $display("[ICEAppSim] sim_spiRst_ === 1'b1 ✅");
    end else begin
        $display("[ICEAppSim] sim_spiRst_ !== 1'b1 ❌ (%b)", sim_spiRst_);
        `Finish;
    end
    
    spi_dataOutEn = 0;
end endtask

// TestSDCheckCMD6AccessMode: required by TestSDCMD6
task TestSDCMD6_CheckAccessMode; begin
    // Check the access mode from the CMD6 response
    if (spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits] === 4'h3) begin
        $display("[ICEAppSim] CMD6 access mode == 0x3 ✅");
    end else begin
        $display("[ICEAppSim] CMD6 access mode == 0x%h ❌", spi_resp[`Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits]);
        `Finish;
    end
end endtask

task TestSDReadoutToSPI_Readout; begin
    $display("[ICEAppSim] TestSDReadoutToSPI_Readout unsupported");
    `Finish;
end endtask

task TestImgReadoutToSPI_Readout(input[`Msg_Arg_ImgReadout_Thumb_Len-1:0] thumb); begin
    $display("[ICEAppSim] TestImgReadoutToSPI_Readout unsupported");
    `Finish;
end endtask
