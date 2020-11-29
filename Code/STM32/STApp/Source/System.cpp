#include "System.h"
#include "Assert.h"
#include "Abort.h"
#include "SystemClock.h"
#include "Startup.h"
#include <string.h>

System::System() :
ice40(qspi) {
}

void System::init() {
    _super::init();
}

ICE40::SDGetStatusResp System::_sdGetStatus() {
    return ice40.sendMsgWithResp<SDGetStatusResp>(SDGetStatusMsg());
}

ICE40::SDGetStatusResp System::_sdSendCmd(uint8_t sdCmd, uint32_t sdArg,
    SDSendCmdMsg::RespType respType, SDSendCmdMsg::DatInType datInType) {
    
    ice40.sendMsg(SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
    
    // Wait for command to be sent
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0;; i++) {
        Assert(i < MaxAttempts); // TODO: improve error handling
        if (i >= 10) HAL_Delay(1);
        auto status = _sdGetStatus();
        // Continue if the command hasn't been sent yet
        if (!status.sdCmdDone()) continue;
        // Continue if we expect a response but it hasn't been received yet
        if (respType!=SDRespTypes::None && !status.sdRespDone()) continue;
        // Continue if we expect DatIn but it hasn't been received yet
        if (datInType!=SDDatInTypes::None && !status.sdDatInDone()) continue;
        return status;
    }
}

// Test SD card bulk DatOut writing
void System::_handleEvent() {
    const uint8_t SDClkSlowDelay = 15;
    const uint8_t SDClkFastDelay = 2;
    
    // Confirm that we can communicate with the ICE40
    {
        char str[] = "halla";
        auto status = ice40.sendMsgWithResp<EchoResp>(EchoMsg(str));
        Assert(!strcmp((char*)status.payload, str));
    }
    
    // Disable SD clock
    {
        ice40.sendMsg(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
    }
    
    // Enable SD slow clock
    {
        ice40.sendMsg(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Slow, SDClkSlowDelay));
    }
    
    // ====================
    // CMD0 | GO_IDLE_STATE
    //   State: X -> Idle
    //   Go to idle state
    // ====================
    {
        _sdSendCmd(0, 0, SDRespTypes::None);
        // There's no response to CMD0
    }
    
    // ====================
    // CMD8 | SEND_IF_COND
    //   State: Idle -> Idle
    //   Send interface condition
    // ====================
    {
        auto status = _sdSendCmd(8, 0x000001AA);
        Assert(!status.sdRespCRCErr());
        Assert(status.sdRespGetBits(15,8) == 0xAA); // Verify the response pattern is what we sent
    }
    
    // ====================
    // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
    //   State: Idle -> Ready
    //   Initialize
    // ====================
    bool switchTo1V8 = false;
    for (;;) {
        // CMD55
        {
            auto status = _sdSendCmd(55, 0);
            Assert(!status.sdRespCRCErr());
        }
        
        // CMD41
        {
            auto status = _sdSendCmd(41, 0x51008000);
            // Don't check CRC with .sdRespCRCOK() (the CRC response to ACMD41 is all 1's)
            Assert(status.sdRespGetBits(45,40) == 0x3F); // Command should be 6'b111111
            Assert(status.sdRespGetBits(7,1) == 0x7F); // CRC should be 7'b1111111
            // Check if card is ready. If it's not, retry ACMD41.
            if (!status.sdRespGetBit(39)) continue;
            // Check if we can switch to 1.8V
            // If not, we'll assume we're already in 1.8V mode
            switchTo1V8 = status.sdRespGetBit(32);
            break;
        }
    }
    
    if (switchTo1V8) {
        // ====================
        // CMD11 | VOLTAGE_SWITCH
        //   State: Ready -> Ready
        //   Switch to 1.8V signaling voltage
        // ====================
        {
            auto status = _sdSendCmd(11, 0);
            Assert(!status.sdRespCRCErr());
        }
        
        // Disable SD clock for 5ms (SD clock source = none)
        {
            ice40.sendMsg(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
            HAL_Delay(5);
        }
        
        // Re-enable the SD clock
        {
            ice40.sendMsg(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Slow, SDClkSlowDelay));
        }
        
        // Wait for SD card to indicate that it's ready (DAT0=1)
        {
            for (;;) {
                auto status = _sdGetStatus();
                if (status.sdDat0Idle()) break;
                // Busy
            }
            // Ready
        }
    }
    
    
    
    
    // ====================
    // CMD2 | ALL_SEND_CID
    //   State: Ready -> Identification
    //   Get card identification number (CID)
    // ====================
    {
        // The response to CMD2 is 136 bits, instead of the usual 48 bits
        _sdSendCmd(2, 0, SDRespTypes::Len136);
        // Don't check the CRC because the R2 CRC isn't calculated in the typical manner,
        // so it'll be flagged as incorrect.
    }
    
    // ====================
    // CMD3 | SEND_RELATIVE_ADDR
    //   State: Identification -> Standby
    //   Publish a new relative address (RCA)
    // ====================
    uint16_t rca = 0;
    {
        auto status = _sdSendCmd(3, 0);
        Assert(!status.sdRespCRCErr());
        // Get the card's RCA from the response
        rca = status.sdRespGetBits(39,24);
    }
    
    // ====================
    // CMD7 | SELECT_CARD/DESELECT_CARD
    //   State: Standby -> Transfer
    //   Select card
    // ====================
    {
        auto status = _sdSendCmd(7, ((uint32_t)rca)<<16);
        Assert(!status.sdRespCRCErr());
    }
    
    // ====================
    // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
    //   State: Transfer -> Transfer
    //   Set bus width to 4 bits
    // ====================
    {
        // CMD55
        {
            auto status = _sdSendCmd(55, ((uint32_t)rca)<<16);
            Assert(!status.sdRespCRCErr());
        }
        
        // CMD6
        {
            auto status = _sdSendCmd(6, 0x00000002);
            Assert(!status.sdRespCRCErr());
        }
    }
    
    // ====================
    // CMD6 | SWITCH_FUNC
    //   State: Transfer -> Data
    //   Switch to SDR104
    // ====================
    {
        // Mode = 1 (switch function)  = 0x80
        // Group 6 (Reserved)          = 0xF (no change)
        // Group 5 (Reserved)          = 0xF (no change)
        // Group 4 (Current Limit)     = 0xF (no change)
        // Group 3 (Driver Strength)   = 0xF (no change; 0x0=TypeB[1x], 0x1=TypeA[1.5x], 0x2=TypeC[.75x], 0x3=TypeD[.5x])
        // Group 2 (Command System)    = 0xF (no change)
        // Group 1 (Access Mode)       = 0x3 (SDR104)
        auto status = _sdSendCmd(6, 0x80FFFFF3, SDRespTypes::Len48, SDDatInTypes::Len512);
        Assert(!status.sdRespCRCErr());
        Assert(!status.sdDatInCRCErr());
        // Verify that the access mode was successfully changed
        // TODO: properly handle this failing, see CMD6 docs
        Assert(status.sdDatInCMD6AccessMode() == 0x03);
    }
    
    // Disable SD clock
    {
        ice40.sendMsg(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
    }
    
    // Switch to the fast delay
    {
        ice40.sendMsg(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkFastDelay));
    }
    
    // Enable SD fast clock
    {
        ice40.sendMsg(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Fast, SDClkFastDelay));
    }
    
    bool on = true;
    for (volatile uint32_t iter=0;; iter++) {
        // ====================
        // ACMD23 | SET_WR_BLK_ERASE_COUNT
        //   State: Transfer -> Transfer
        //   Set the number of blocks to be
        //   pre-erased before writing
        // ====================
        {
            // CMD55
            {
                auto status = _sdSendCmd(55, ((uint32_t)rca)<<16);
                Assert(!status.sdRespCRCErr());
            }
            
            // CMD23
            {
                auto status = _sdSendCmd(23, 0x00000001);
                Assert(!status.sdRespCRCErr());
            }
        }
        
        // ====================
        // CMD25 | WRITE_MULTIPLE_BLOCK
        //   State: Transfer -> Receive Data
        //   Write blocks of data
        // ====================
        {
            auto status = _sdSendCmd(25, 0);
            Assert(!status.sdRespCRCErr());
        }
        
        // Clock out data on DAT lines
        {
            ice40.sendMsg(PixReadoutMsg(0));
        }
        
        // Wait until we're done clocking out data on DAT lines
        {
            // Waiting for writing to finish
            for (;;) {
                auto status = _sdGetStatus();
                if (status.sdDatOutDone()) {
                    if (status.sdDatOutCRCErr()) {
                        led3.write(true);
                        for (;;);
                    }
                    break;
                }
                // Busy
            }
        }
        
        // ====================
        // CMD12 | STOP_TRANSMISSION
        //   State: Receive Data -> Programming
        //   Finish writing
        // ====================
        {
            auto status = _sdSendCmd(12, 0);
            Assert(!status.sdRespCRCErr());
            
            // Wait for SD card to indicate that it's ready (DAT0=1)
            for (;;) {
                if (status.sdDat0Idle()) break;
                status = _sdGetStatus();
            }
        }
        
        led0.write(on);
        on = !on;
    }
    
    for (;;);
}




ICE40::PixGetStatusResp System::_pixGetStatus() {
    return ice40.sendMsgWithResp<PixGetStatusResp>(PixGetStatusMsg());
}

uint16_t System::_pixRead(uint16_t addr) {
    ice40.sendMsg(PixI2CTransactionMsg(false, 2, addr, 0));
    
    // Wait for the I2C transaction to complete
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0;; i++) {
        Assert(i < MaxAttempts); // TODO: improve error handling
        if (i >= 10) HAL_Delay(1);
        auto status = _pixGetStatus();
        // Continue if the I2C transaction isn't complete yet
        if (!status.i2cDone()) continue;
        Assert(!status.i2cErr()); // TODO: improve error handling
        return status.i2cReadData();
    }
}

void System::_pixWrite(uint16_t addr, uint16_t val) {
    ice40.sendMsg(PixI2CTransactionMsg(true, 2, addr, val));
    
    // Wait for the I2C transaction to complete
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0;; i++) {
        Assert(i < MaxAttempts); // TODO: improve error handling
        if (i >= 10) HAL_Delay(1);
        auto status = _pixGetStatus();
        // Continue if the I2C transaction isn't complete yet
        if (!status.i2cDone()) continue;
        Assert(!status.i2cErr()); // TODO: improve error handling
        return;
    }
}



//// Test image capture
//void System::_handleEvent() {
//    // Confirm that we can communicate with the ICE40
//    {
//        char str[] = "halla";
//        auto status = ice40.sendMsgWithResp<EchoResp>(EchoMsg(str));
//        Assert(!strcmp((char*)status.payload, str));
//    }
//    
//    // Assert/deassert pix reset
//    {
//        ice40.sendMsg(PixResetMsg(false));
//        HAL_Delay(1);
//        ice40.sendMsg(PixResetMsg(true));
//        // Wait 150k EXTCLK (24MHz) periods
//        // (150e3*(1/24e6)) == 6.25ms
//        HAL_Delay(7);
//    }
//    
//    // Sanity-check pix comms by reading a known register
//    {
//        const uint16_t chipVersion = _pixRead(0x3000);
//        // TODO: we probably don't want to check the version number in production, in case the version number changes?
//        // also the 0x3000 isn't read-only, so in theory it could change
//        Assert(chipVersion == 0x2604);
//    }
//    
//    // Configure internal register initialization
//    {
//        _pixWrite(0x3052, 0xA114);
//    }
//    
//    // Start internal register initialization
//    {
//        _pixWrite(0x304A, 0x0070);
//    }
//    
//    // Wait 150k EXTCLK (24MHz) periods
//    // (150e3*(1/24e6)) == 6.25ms
//    {
//        HAL_Delay(7);
//    }
//    
//    // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
//    // (Default value of 0x301A is 0x0058)
//    {
//        _pixWrite(0x301A, 0x10D8);
//    }
//    
//    // Set pre_pll_clk_div
//    {
////        _pixWrite(0x302E, 0x0002);  // /2 -> CLK_OP=98 MHz
////        _pixWrite(0x302E, 0x0004);  // /4 -> CLK_OP=49 MHz (Default)
////        _pixWrite(0x302E, 0x003F);  // /63
//    }
//    
//    // Set pll_multiplier
//    {
////        _pixWrite(0x3030, 0x0062);  // *98 (Default)
////        _pixWrite(0x3030, 0x0031);  // *49
//    }
//    
//    // Set vt_pix_clk_div
//    {
////        _pixWrite(0x302A, 0x0006);  // /6 (Default)
////        _pixWrite(0x302A, 0x001F);  // /31
//    }
//    
//    // Set op_pix_clk_div
//    {
////        _pixWrite(0x3036, 0x000A);
//    }
//    
//    // Set output slew rate
//    {
////        _pixWrite(0x306E, 0x0010);  // Slow
////        _pixWrite(0x306E, 0x9010);  // Medium (default)
//        _pixWrite(0x306E, 0xFC10);  // Fast
//    }
//    
//    // Set data_pedestal
//    {
////        _pixWrite(0x301E, 0x00A8);  // Default
////        _pixWrite(0x301E, 0x0000);
//    }
//    
//    // Set test data colors
//    {
////        // Set test_data_red
////        _pixWrite(0x3072, 0x0B2A);  // AAA
////        _pixWrite(0x3072, 0x0FFF);  // FFF
////
////        // Set test_data_greenr
////        _pixWrite(0x3074, 0x0C3B);  // BBB
////        _pixWrite(0x3074, 0x0FFF);  // FFF
////
////        // Set test_data_blue
////        _pixWrite(0x3076, 0x0D4C);  // CCC
////        _pixWrite(0x3076, 0x0FFF);  // FFF
////
////        // Set test_data_greenb
////        _pixWrite(0x3078, 0x0C3B);  // BBB
////        _pixWrite(0x3078, 0x0FFF);  // FFF
//    }
//    
//    // Set test_pattern_mode
//    {
//        // 0: Normal operation (generate output data from pixel array)
//        // 1: Solid color test pattern.
//        // 2: Full color bar test pattern
//        // 3: Fade-to-gray color bar test pattern
//        // 256: Walking 1s test pattern (12 bit)
////        _pixWrite(0x3070, 0x0000);  // Normal operation
////        _pixWrite(0x3070, 0x0001);  // Solid color
////        _pixWrite(0x3070, 0x0002);  // Color bars
////        _pixWrite(0x3070, 0x0003);  // Fade-to-gray
////        _pixWrite(0x3070, 0x0100);  // Walking 1s
//    }
//    
//    // Set serial_format
//    // *** This register write is necessary for parallel mode.
//    // *** The datasheet doesn't mention this. :(
//    // *** Discovered looking at Linux kernel source.
//    {
//        _pixWrite(0x31AE, 0x0301);
//    }
//    
//    // Set data_format_bits
//    // Datasheet:
//    //   "The serial format should be configured using R0x31AC.
//    //   This register should be programmed to 0x0C0C when
//    //   using the parallel interface."
//    {
//        _pixWrite(0x31AC, 0x0C0C);
//    }
//    
//    // Set row_speed
//    {
////        _pixWrite(0x3028, 0x0000);  // 0 cycle delay
////        _pixWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
//    }
//
//    // Set the x-start address
//    {
////        _pixWrite(0x3004, 0x0006);  // Default
////        _pixWrite(0x3004, 0x0010);
//    }
//
//    // Set the x-end address
//    {
////        _pixWrite(0x3008, 0x0905);  // Default
////        _pixWrite(0x3008, 0x01B1);
//    }
//
//    // Set the y-start address
//    {
////        _pixWrite(0x3002, 0x007C);  // Default
////        _pixWrite(0x3002, 0x007C);
//    }
//
//    // Set the y-end address
//    {
////        _pixWrite(0x3006, 0x058b);  // Default
////        _pixWrite(0x3006, 0x016B);
//    }
//    
//    // Implement "Recommended Default Register Changes and Sequencer"
//    {
//        _pixWrite(0x3ED2, 0x0146);
//        _pixWrite(0x3EDA, 0x88BC);
//        _pixWrite(0x3EDC, 0xAA63);
//        _pixWrite(0x305E, 0x00A0);
//    }
//    
//    // Disable embedded_data (first 2 rows of statistic info)
//    // See AR0134_RR_D.pdf for info on statistics format
//    {
////        _pixWrite(0x3064, 0x1902);  // Stats enabled (default)
//        _pixWrite(0x3064, 0x1802);  // Stats disabled
//    }
//    
//    // Start streaming
//    // (Previous value of 0x301A is 0x10D8, as set above)
//    {
//        _pixWrite(0x301A, 0x10DC);
//    }
//    
//    // Capture a frame
//    for (bool ledOn=true;; ledOn=!ledOn) {
//        led0.write(ledOn);
//        ice40.sendMsg(PixCaptureMsg(0));
//        for (int i=0; i<10; i++) {
//            auto status = _pixGetStatus();
//            Assert(!status.capturePixelDropped());
//            if (status.captureDone()) break;
//            Assert(i < 10);
//        }
//        HAL_Delay(33);
//    }
//    
//    for (;;);
//}
//
//void System::_usbHandleEvent(const USB::Event& ev) {
//    using Type = USB::Event::Type;
//    switch (ev.type) {
//    case Type::StateChanged: {
//        // Handle USB connection
//        if (usb.state() == USB::State::Connected) {
//            // Handle USB connected
//        }
//        break;
//    }
//    
//    default: {
//        // Invalid event type
//        Abort();
//    }}
//}

System Sys;

int main() {
    Sys.init();
    // Event loop
    for (;;) {
        Sys._handleEvent();
    }
    return 0;
}
