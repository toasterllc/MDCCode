#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "ICE40.h"

using EchoMsg = ICE40::EchoMsg;
using EchoResp = ICE40::EchoResp;
using LEDSetMsg = ICE40::LEDSetMsg;
using SDInitMsg = ICE40::SDInitMsg;
using SDSendCmdMsg = ICE40::SDSendCmdMsg;
using SDStatusMsg = ICE40::SDStatusMsg;
using SDStatusResp = ICE40::SDStatusResp;
using ImgResetMsg = ICE40::ImgResetMsg;
using ImgCaptureMsg = ICE40::ImgCaptureMsg;
using ImgReadoutMsg = ICE40::ImgReadoutMsg;
using ImgI2CTransactionMsg = ICE40::ImgI2CTransactionMsg;
using ImgI2CStatusMsg = ICE40::ImgI2CStatusMsg;
using ImgI2CStatusResp = ICE40::ImgI2CStatusResp;
using ImgCaptureStatusMsg = ICE40::ImgCaptureStatusMsg;
using ImgCaptureStatusResp = ICE40::ImgCaptureStatusResp;

using SDRespTypes = ICE40::SDSendCmdMsg::RespTypes;
using SDDatInTypes = ICE40::SDSendCmdMsg::DatInTypes;

constexpr uint64_t MCLKFreqHz = 16000000;

#define _delayUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000);
#define _delayMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000);

static void _clockInit() {
    constexpr uint32_t XT1FreqHz = 32768;
    
    // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
    // This must happen before configuring the clock system.
    FRCTL0 = FRCTLPW | NWAITS_1;
    
    // Make PA.8 and PA.9 XOUT/XIN
    PASEL1 |=  (BIT8 | BIT9);
    PASEL0 &= ~(BIT8 | BIT9);
    
    do {
        CSCTL7 &= ~(XT1OFFG | DCOFFG); // Clear XT1 and DCO fault flag
        SFRIFG1 &= ~OFIFG;
    } while (SFRIFG1 & OFIFG); // Test oscillator fault flag
    
    // Disable FLL
    __bis_SR_register(SCG0);
        // Set XT1 as FLL reference source
        CSCTL3 |= SELREF__XT1CLK;
        // Clear DCO and MOD registers
        CSCTL0 = 0;
        // Clear DCO frequency select bits first
        CSCTL1 &= ~(DCORSEL_7);
        // Set DCO = 16MHz
        CSCTL1 |= DCORSEL_5;
        // DCOCLKDIV = 16MHz
        CSCTL2 = FLLD_0 | ((MCLKFreqHz/XT1FreqHz)-1);
        // Wait 3 cycles to take effect
        __delay_cycles(3);
    // Enable FLL
    __bic_SR_register(SCG0);
    
    // Wait until FLL locks
    while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
    
    // MCLK / SMCLK source = DCOCLKDIV
    // ACLK source = XT1
    CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
}

static void _sysInit() {
    // Stop watchdog timer
    {
        WDTCTL = WDTPW | WDTHOLD;
    }
    
    // Reset pin states
    {
        PAOUT   = 0x0000;
        PADIR   = 0x0000;
        PASEL0  = 0x0000;
        PASEL1  = 0x0000;
        PAREN   = 0x0000;
    }
    
    // Configure clock system
    {
        _clockInit();
    }
    
    // Unlock GPIOs
    {
        PM5CTL0 &= ~LOCKLPM5;
    }
}

static void _spiInit() {
    // Reset the ICE40 SPI state machine by asserting ice_msp_spi_clk for some period
    {
        constexpr uint64_t ICE40SPIResetDurationUs = 18;
        
        // PA.6 = GPIO output
        PAOUT  &= ~BIT6;
        PADIR  |=  BIT6;
        PASEL1 &= ~BIT6;
        PASEL0 &= ~BIT6;
        
        PAOUT  |=  BIT6;
        _delayUs(ICE40SPIResetDurationUs);
        PAOUT  &= ~BIT6;
    }
    
    // Configure SPI peripheral
    {
        // PA.3 = GPIO output
        PAOUT  &= ~BIT3;
        PADIR  |=  BIT3;
        PASEL1 &= ~BIT3;
        PASEL0 &= ~BIT3;
        
        // PA.4 = GPIO input
        PADIR  &= ~BIT4;
        PASEL1 &= ~BIT4;
        PASEL0 &= ~BIT4;
        
        // PA.5 = UCA0SOMI
        PASEL1 &= ~BIT5;
        PASEL0 |=  BIT5;
        
        // PA.6 = UCA0CLK
        PASEL1 &= ~BIT6;
        PASEL0 |=  BIT6;
        
        // Assert USCI reset
        UCA0CTLW0 |= UCSWRST;
        
        UCA0CTLW0 |=
            // phase=1, polarity=0, MSB first, width=8-bit
            UCCKPH_1 | UCCKPL__LOW | UCMSB_1 | UC7BIT__8BIT |
            // mode=master, mode=3-pin SPI, mode=synchronous, clock=SMCLK
            UCMST__MASTER | UCMODE_0 | UCSYNC__SYNC | UCSSEL__SMCLK;
        
        // fBitClock = fBRCLK / 1;
        UCA0BRW = 0;
        // No modulation
        UCA0MCTLW = 0;
        
        // De-assert USCI reset
        UCA0CTLW0 &= ~UCSWRST;
    }
}

static uint8_t _spiTxRx(uint8_t b) {
    // Wait until `UCA0TXBUF` can accept more data
    while (!(UCA0IFG & UCTXIFG));
    // Clear UCRXIFG so we can tell when tx/rx is complete
    UCA0IFG &= ~UCRXIFG;
    // Start the SPI transaction
    UCA0TXBUF = b;
    // Wait for tx completion
    // Wait for UCRXIFG, not UCTXIFG! UCTXIFG signifies that UCA0TXBUF
    // can accept more data, not transfer completion. UCRXIFG signifies
    // rx completion, which implies tx completion.
    while (!(UCA0IFG & UCRXIFG));
    return UCA0RXBUF;
}

static void _ice40Transfer(const ICE40::Msg& msg, ICE40::Resp& resp) {
    // PA.4 = UCA0SIMO
    PASEL1 &= ~BIT4;
    PASEL0 |=  BIT4;
    
    // PA.4 level shifter direction = MSP->ICE
    PAOUT |= BIT3;
    
    _spiTxRx(msg.type);
    
    for (uint8_t b : msg.payload) {
        _spiTxRx(b);
    }
    
    // PA.4 = GPIO input
    PASEL1 &= ~BIT4;
    PASEL0 &= ~BIT4;
    
    // PA.4 level shifter direction = MSP<-ICE
    PAOUT &= ~BIT3;
    
    // 8-cycle turnaround
    _spiTxRx(0xFF);
    
    for (uint8_t& b : resp.payload) {
        b = _spiTxRx(0xFF);
    }
}

static void _ice40Transfer(const ICE40::Msg& msg) {
    ICE40::Resp resp;
    _ice40Transfer(msg, resp);
}

SDStatusResp _sdStatus() {
    SDStatusResp resp;
    _ice40Transfer(SDStatusMsg(), resp);
    return resp;
}

SDStatusResp _sdSendCmd(
    uint8_t sdCmd,
    uint32_t sdArg,
    SDSendCmdMsg::RespType respType=ICE40::SDSendCmdMsg::RespTypes::Len48,
    SDSendCmdMsg::DatInType datInType=ICE40::SDSendCmdMsg::DatInTypes::None
) {
    _ice40Transfer(SDSendCmdMsg(sdCmd, sdArg, respType, datInType));
    
    // Wait for command to be sent
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0;; i++) {
        Assert(i < MaxAttempts); // TODO: improve error handling
        if (i >= 10) _delayMs(1);
        auto status = _sdStatus();
        // Try again if the command hasn't been sent yet
        if (!status.cmdDone()) continue;
        // Try again if we expect a response but it hasn't been received yet
        if (respType!=SDRespTypes::None && !status.respDone()) continue;
        // Try again if we expect DatIn but it hasn't been received yet
        if (datInType!=SDDatInTypes::None && !status.datInDone()) continue;
        return status;
    }
}

void _sdSetPowerEnabled(bool en) {
    constexpr uint16_t VDD_SD_EN = BITB;
    if (en) {
        PADIR |=  VDD_SD_EN;
        PAOUT |=  VDD_SD_EN;
    } else {
        PADIR |=  VDD_SD_EN;
        PAOUT &= ~VDD_SD_EN;
    }
}

uint16_t _sdInit() {
    const uint8_t SDClkDelaySlow = 15;
    const uint8_t SDClkDelayFast = 2;
    
    // Turn off SD card power and wait for it to reach 0V
    _sdSetPowerEnabled(false);
    _delayMs(2);
    // InitMode=Enabled, Clock=Off
    _ice40Transfer(SDInitMsg(SDInitMsg::State::Enabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Off, SDClkDelaySlow));
    // Clock=SlowClock
    _ice40Transfer(SDInitMsg(SDInitMsg::State::Enabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Slow, SDClkDelaySlow));
    // Turn on SD card power and wait for it to reach 2.8V
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _sdSetPowerEnabled(true);
    _delayMs(2);
    // Trigger the SD card low voltage signalling (LVS) init sequence
    _ice40Transfer(SDInitMsg(SDInitMsg::State::Enabled, SDInitMsg::Trigger::Trigger, SDInitMsg::ClkSpeed::Slow, SDClkDelaySlow));
    // Wait 5ms for the LVS init sequence to complete (per the LVS spec)
    _delayMs(5);
    // InitMode=Disabled
    _ice40Transfer(SDInitMsg(SDInitMsg::State::Disabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Slow, SDClkDelaySlow));
    
//    TestSDConfig(0, `Msg_Arg_SDInit_ClkSrc_Speed_Off,  0, 0); // Disable SD clock, enable SD init mode
//    TestSDConfig(0, `Msg_Arg_SDInit_ClkSrc_Speed_Slow, 0, 0); // SD clock = slow clock
//    TestSDConfig(0, `Msg_Arg_SDInit_ClkSrc_Speed_Slow, 0, 1); // Reset SDController's `init` state machine
//    // <-- Turn on power to SD card
//    TestSDConfig(0, `Msg_Arg_SDInit_ClkSrc_Speed_Slow, 1, 0); // Trigger SDController init state machine
//    
//    // Wait for SD init to be complete
//    done = 0;
//    for (i=0; i<10 && !done; i++) begin
//        // Request SD status
//        SendMsg(`Msg_Type_SDStatus, 0);
//        // We're done when the `InitDone` bit is set
//        done = spi_resp[`Resp_Arg_SDStatus_InitDone_Bits];
//    end
    
//    // Disable SD clock
//    {
//        _ice40Transfer(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
//    }
//    
//    // Enable SD slow clock
//    {
//        _ice40Transfer(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Slow, SDClkSlowDelay));
//    }
    
    // ====================
    // CMD0 | GO_IDLE_STATE
    //   State: X -> Idle
    //   Go to idle state
    // ====================
    {
        // SD "Initialization sequence": wait max(1ms, 74 cycles @ 400 kHz) == 1ms
        _delayMs(1);
        // Send CMD0
        _sdSendCmd(0, 0, SDRespTypes::None);
        // There's no response to CMD0
    }
    
    // ====================
    // CMD8 | SEND_IF_COND
    //   State: Idle -> Idle
    //   Send interface condition
    // ====================
    {
        constexpr uint32_t Voltage       = 0x00000002; // 0b0010 == 'Low Voltage Range'
        constexpr uint32_t CheckPattern  = 0x000000AA; // "It is recommended to use '10101010b' for the 'check pattern'"
        auto status = _sdSendCmd(8, (Voltage<<8)|(CheckPattern<<0));
        Assert(!status.respCRCErr());
        const uint8_t replyVoltage = status.respGetBits(19,16);
        Assert(replyVoltage == Voltage);
        const uint8_t replyCheckPattern = status.respGetBits(15,8);
        Assert(replyCheckPattern == CheckPattern);
    }
    
    // ====================
    // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
    //   State: Idle -> Ready
    //   Initialize
    // ====================
    for (;;) {
        // CMD55
        {
            auto status = _sdSendCmd(55, 0);
            Assert(!status.respCRCErr());
        }
        
        // CMD41
        {
            auto status = _sdSendCmd(41, 0x51008000);
            // Don't check CRC with .respCRCOK() (the CRC response to ACMD41 is all 1's)
            Assert(status.respGetBits(45,40) == 0x3F); // Command should be 6'b111111
            Assert(status.respGetBits(7,1) == 0x7F); // CRC should be 7'b1111111
            // Check if card is ready. If it's not, retry ACMD41.
            const bool ready = status.respGetBit(39);
            if (!ready) continue;
            // Check S18A; for LVS initialization, it's expected to be 0
            const bool S18A = status.respGetBit(32);
            Assert(S18A == 0);
            break;
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
        Assert(!status.respCRCErr());
        // Get the card's RCA from the response
        rca = status.respGetBits(39,24);
    }
    
    // ====================
    // CMD7 | SELECT_CARD/DESELECT_CARD
    //   State: Standby -> Transfer
    //   Select card
    // ====================
    {
        auto status = _sdSendCmd(7, ((uint32_t)rca)<<16);
        Assert(!status.respCRCErr());
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
            Assert(!status.respCRCErr());
        }
        
        // CMD6
        {
            auto status = _sdSendCmd(6, 0x00000002);
            Assert(!status.respCRCErr());
        }
    }
    
    // ====================
    // CMD6 | SWITCH_FUNC
    //   State: Transfer -> Data -> Transfer (automatically returns to Transfer state after sending 512 bits of data)
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
        Assert(!status.respCRCErr());
        Assert(!status.datInCRCErr());
        // Verify that the access mode was successfully changed
        // TODO: properly handle this failing, see CMD6 docs
        Assert(status.datInCMD6AccessMode() == 0x03);
    }
    
    // SDClock=Off
    {
        _ice40Transfer(SDInitMsg(SDInitMsg::State::Disabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Off, SDClkDelaySlow));
    }
    
    // SDClockDelay=FastDelay
    {
        _ice40Transfer(SDInitMsg(SDInitMsg::State::Disabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Off, SDClkDelayFast));
    }
    
    // SDClock=FastClock
    {
        _ice40Transfer(SDInitMsg(SDInitMsg::State::Disabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Fast, SDClkDelayFast));
    }
    
    
//    // ====================
//    // ACMD41 (CMD55, CMD41) | SD_SEND_OP_COND
//    //   State: Idle -> Ready
//    //   Initialize
//    // ====================
//    bool switchTo1V8 = false;
//    for (;;) {
//        // CMD55
//        {
//            auto status = _sdSendCmd(55, 0);
//            Assert(!status.respCRCErr());
//        }
//        
//        // CMD41
//        {
//            auto status = _sdSendCmd(41, 0x51008000);
//            // Don't check CRC with .respCRCOK() (the CRC response to ACMD41 is all 1's)
//            Assert(status.respGetBits(45,40) == 0x3F); // Command should be 6'b111111
//            Assert(status.respGetBits(7,1) == 0x7F); // CRC should be 7'b1111111
//            // Check if card is ready. If it's not, retry ACMD41.
//            if (!status.respGetBit(39)) continue;
//            // Check if we can switch to 1.8V
//            // If not, we'll assume we're already in 1.8V mode
//            switchTo1V8 = status.respGetBit(32);
//            break;
//        }
//    }
//    
//    if (switchTo1V8) {
//        // ====================
//        // CMD11 | VOLTAGE_SWITCH
//        //   State: Ready -> Ready
//        //   Switch to 1.8V signaling voltage
//        // ====================
//        {
//            auto status = _sdSendCmd(11, 0);
//            Assert(!status.respCRCErr());
//        }
//        
//        // Disable SD clock for 5ms (SD clock source = none)
//        {
//            _ice40Transfer(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
//            HAL_Delay(5);
//        }
//        
//        // Re-enable the SD clock
//        {
//            _ice40Transfer(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Slow, SDClkSlowDelay));
//        }
//        
//        // Wait for SD card to indicate that it's ready (DAT0=1)
//        {
//            for (;;) {
//                auto status = _sdStatus();
//                if (status.dat0Idle()) break;
//                // Busy
//            }
//            // Ready
//        }
//    }
//    
//    
//    
//    
//    // ====================
//    // CMD2 | ALL_SEND_CID
//    //   State: Ready -> Identification
//    //   Get card identification number (CID)
//    // ====================
//    {
//        // The response to CMD2 is 136 bits, instead of the usual 48 bits
//        _sdSendCmd(2, 0, SDRespTypes::Len136);
//        // Don't check the CRC because the R2 CRC isn't calculated in the typical manner,
//        // so it'll be flagged as incorrect.
//    }
//    
//    // ====================
//    // CMD3 | SEND_RELATIVE_ADDR
//    //   State: Identification -> Standby
//    //   Publish a new relative address (RCA)
//    // ====================
//    uint16_t rca = 0;
//    {
//        auto status = _sdSendCmd(3, 0);
//        Assert(!status.respCRCErr());
//        // Get the card's RCA from the response
//        rca = status.respGetBits(39,24);
//    }
//    
//    // ====================
//    // CMD7 | SELECT_CARD/DESELECT_CARD
//    //   State: Standby -> Transfer
//    //   Select card
//    // ====================
//    {
//        auto status = _sdSendCmd(7, ((uint32_t)rca)<<16);
//        Assert(!status.respCRCErr());
//    }
//    
//    // ====================
//    // ACMD6 (CMD55, CMD6) | SET_BUS_WIDTH
//    //   State: Transfer -> Transfer
//    //   Set bus width to 4 bits
//    // ====================
//    {
//        // CMD55
//        {
//            auto status = _sdSendCmd(55, ((uint32_t)rca)<<16);
//            Assert(!status.respCRCErr());
//        }
//        
//        // CMD6
//        {
//            auto status = _sdSendCmd(6, 0x00000002);
//            Assert(!status.respCRCErr());
//        }
//    }
//    
//    // ====================
//    // CMD6 | SWITCH_FUNC
//    //   State: Transfer -> Data -> Transfer (automatically returns to Transfer state after sending 512 bits of data)
//    //   Switch to SDR104
//    // ====================
//    {
//        // Mode = 1 (switch function)  = 0x80
//        // Group 6 (Reserved)          = 0xF (no change)
//        // Group 5 (Reserved)          = 0xF (no change)
//        // Group 4 (Current Limit)     = 0xF (no change)
//        // Group 3 (Driver Strength)   = 0xF (no change; 0x0=TypeB[1x], 0x1=TypeA[1.5x], 0x2=TypeC[.75x], 0x3=TypeD[.5x])
//        // Group 2 (Command System)    = 0xF (no change)
//        // Group 1 (Access Mode)       = 0x3 (SDR104)
//        auto status = _sdSendCmd(6, 0x80FFFFF3, SDRespTypes::Len48, SDDatInTypes::Len512);
//        Assert(!status.respCRCErr());
//        Assert(!status.datInCRCErr());
//        // Verify that the access mode was successfully changed
//        // TODO: properly handle this failing, see CMD6 docs
//        Assert(status.datInCMD6AccessMode() == 0x03);
//    }
//    
//    // Disable SD clock
//    {
//        _ice40Transfer(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkSlowDelay));
//    }
//    
//    // Switch to the fast delay
//    {
//        _ice40Transfer(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Off, SDClkFastDelay));
//    }
//    
//    // Enable SD fast clock
//    {
//        _ice40Transfer(SDClkSrcMsg(SDClkSrcMsg::ClkSpeed::Fast, SDClkFastDelay));
//    }
//    
//    bool on = true;
//    for (volatile uint32_t iter=0;; iter++) {
//        // ====================
//        // ACMD23 | SET_WR_BLK_ERASE_COUNT
//        //   State: Transfer -> Transfer
//        //   Set the number of blocks to be
//        //   pre-erased before writing
//        // ====================
//        {
//            // CMD55
//            {
//                auto status = _sdSendCmd(55, ((uint32_t)rca)<<16);
//                Assert(!status.respCRCErr());
//            }
//            
//            // CMD23
//            {
//                auto status = _sdSendCmd(23, 0x00000001);
//                Assert(!status.respCRCErr());
//            }
//        }
//        
//        // ====================
//        // CMD25 | WRITE_MULTIPLE_BLOCK
//        //   State: Transfer -> Receive Data
//        //   Write blocks of data
//        // ====================
//        {
//            auto status = _sdSendCmd(25, 0);
//            Assert(!status.respCRCErr());
//        }
//        
//        // Clock out data on DAT lines
//        {
//            _ice40Transfer(PixReadoutMsg(0));
//        }
//        
//        // Wait until we're done clocking out data on DAT lines
//        {
//            // Waiting for writing to finish
//            for (;;) {
//                auto status = _sdStatus();
//                if (status.datOutDone()) {
//                    if (status.datOutCRCErr()) {
//                        _led3.write(true);
//                        for (;;);
//                    }
//                    break;
//                }
//                // Busy
//            }
//        }
//        
//        // ====================
//        // CMD12 | STOP_TRANSMISSION
//        //   State: Receive Data -> Programming
//        //   Finish writing
//        // ====================
//        {
//            auto status = _sdSendCmd(12, 0);
//            Assert(!status.respCRCErr());
//            
//            // Wait for SD card to indicate that it's ready (DAT0=1)
//            for (;;) {
//                if (status.dat0Idle()) break;
//                status = _sdStatus();
//            }
//        }
//        
//        _led0.write(on);
//        on = !on;
//    }
    
    return rca;
}

void _sdWriteImage(uint16_t rca) {
    // TODO: calculate the correct number of blocks to pre-erase with SET_WR_BLK_ERASE_COUNT
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
            Assert(!status.respCRCErr());
        }
        
        // CMD23
        {
            auto status = _sdSendCmd(23, 0x00000001);
            Assert(!status.respCRCErr());
        }
    }
    
    // ====================
    // CMD25 | WRITE_MULTIPLE_BLOCK
    //   State: Transfer -> Receive Data
    //   Write blocks of data
    // ====================
    {
        auto status = _sdSendCmd(25, 0);
        Assert(!status.respCRCErr());
    }
    
    // Clock out the image on the DAT lines
    {
        _ice40Transfer(ImgReadoutMsg());
    }
    
    // Wait until we're done clocking out the image on the DAT lines
    {
        // Waiting for writing to finish
        for (;;) {
            auto status = _sdStatus();
            if (status.datOutDone()) {
                Assert(!status.datOutCRCErr());
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
        Assert(!status.respCRCErr());
        
        // Wait for SD card to indicate that it's ready (DAT0=1)
        for (;;) {
            if (status.dat0Idle()) break;
            status = _sdStatus();
        }
    }
}

void _imgSetPowerEnabled(bool en) {
    constexpr uint16_t VDD_1V9_IMG_EN = BIT0;
    constexpr uint16_t VDD_2V8_IMG_EN = BIT2;
    if (en) {
        PADIR |=  VDD_2V8_IMG_EN|VDD_1V9_IMG_EN;
        PAOUT |=  VDD_2V8_IMG_EN;
        _delayUs(100); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        PAOUT |=  VDD_1V9_IMG_EN;
    } else {
        PADIR |=  VDD_2V8_IMG_EN|VDD_1V9_IMG_EN;
        PAOUT &= ~VDD_1V9_IMG_EN;
        // No delay needed for power down (per AR0330CS datasheet)
        PAOUT &= ~VDD_2V8_IMG_EN;
    }
}

ImgI2CStatusResp _imgI2CStatus() {
    ImgI2CStatusResp resp;
    _ice40Transfer(ImgI2CStatusMsg(), resp);
    return resp;
}

uint16_t _imgI2CRead(uint16_t addr) {
    _ice40Transfer(ImgI2CTransactionMsg(false, 2, addr, 0));
    
    // Wait for the I2C transaction to complete
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) _delayMs(1);
        const ImgI2CStatusResp status = _imgI2CStatus();
        if (status.err()) abort();
        if (status.done()) return status.readData();
    }
    // Timeout getting response from ICE40
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

void _imgI2CWrite(uint16_t addr, uint16_t val) {
    _ice40Transfer(ImgI2CTransactionMsg(true, 2, addr, val));
    
    // Wait for the I2C transaction to complete
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0; i<MaxAttempts; i++) {
        if (i >= 10) _delayMs(1);
        const ImgI2CStatusResp status = _imgI2CStatus();
        if (status.done()) {
            if (status.err()) abort();
            return;
        }
    }
    // Timeout getting response from ICE40
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

void _imgInit() {
    _imgSetPowerEnabled(true);
    
    // Toggle IMG_RST_
    {
        _ice40Transfer(ImgResetMsg(0));
        _delayMs(1);
        _ice40Transfer(ImgResetMsg(1));
        // Wait 150k EXTCLK (16MHz) periods
        // (150e3*(1/16e6)) == 9.375ms
        _delayMs(10);
    }
    
    // Configure internal register initialization
    {
        _imgI2CWrite(0x3052, 0xA114);
    }
    
    // Start internal register initialization
    {
        _imgI2CWrite(0x304A, 0x0070);
    }
    
    // Wait 150k EXTCLK (16MHz) periods
    // (150e3*(1/16e6)) == 9.25ms
    {
        _delayMs(10);
    }
    
    // Sanity-check pix comms by reading a known register
    {
        const uint16_t chipVersion = _imgI2CRead(0x3000);
        // TODO: we probably don't want to check the version number in production, in case the version number changes?
        // also the 0x3000 isn't read-only, so in theory it could change
        Assert(chipVersion == 0x2604);
    }
    
    // Enable parallel interface (R0x301A[7]=1), disable serial interface to save power (R0x301A[12]=1)
    // (Default value of 0x301A is 0x0058)
    {
        _imgI2CWrite(0x301A, 0x10D8);
    }
    
    // Set pre_pll_clk_div
    {
        _imgI2CWrite(0x302E, 4);        //  /4 (default)
    }
    
    // Set pll_multiplier
    {
        _imgI2CWrite(0x3030, 147);      //  *147
    }
    
    // Set vt_sys_clk_div
    {
        _imgI2CWrite(0x302C, 1);        //  /1 (default)
    }
    
    // Set vt_pix_clk_div
    {
        _imgI2CWrite(0x302A, 6);        //  /6 (default)
    }
    
//        // Set op_pix_clk_div
//        {
//            _imgI2CWrite(0x3036, 0x000C);
//        }
    
    // Set output slew rate
    {
//        _imgI2CWrite(0x306E, 0x0010);  // Slow
//        _imgI2CWrite(0x306E, 0x9010);  // Medium (default)
        _imgI2CWrite(0x306E, 0xFC10);  // Fast
    }
    
    // Set data_pedestal
    {
//        _imgI2CWrite(0x301E, 0x00A8);  // Default
        _imgI2CWrite(0x301E, 0x0000);
    }
    
    // Set test data colors
    {
//            // Set test_data_red
//            _imgI2CWrite(0x3072, 0x0000);
//            
//            // Set test_data_greenr
//            _imgI2CWrite(0x3074, 0x0000);
//            
//            // Set test_data_blue
//            _imgI2CWrite(0x3076, 0x0000);
//            
//            // Set test_data_greenb
//            _imgI2CWrite(0x3078, 0x0000);
        
//            // Set test_data_red
//            _imgI2CWrite(0x3072, 0x0B2A);  // AAA
//            _imgI2CWrite(0x3072, 0x0FFF);  // FFF
//    
//            // Set test_data_greenr
//            _imgI2CWrite(0x3074, 0x0C3B);  // BBB
//            _imgI2CWrite(0x3074, 0x0FFF);  // FFF
//            _imgI2CWrite(0x3074, 0x0000);
//    
//            // Set test_data_blue
//            _imgI2CWrite(0x3076, 0x0D4C);  // CCC
//            _imgI2CWrite(0x3076, 0x0FFF);  // FFF
//            _imgI2CWrite(0x3076, 0x0000);
//    
//            // Set test_data_greenb
//            _imgI2CWrite(0x3078, 0x0C3B);  // BBB
//            _imgI2CWrite(0x3078, 0x0FFF);  // FFF
//            _imgI2CWrite(0x3078, 0x0000);
        
    }
    
    // Set test_pattern_mode
    {
        // 0: Normal operation (generate output data from pixel array)
        // 1: Solid color test pattern.
        // 2: Full color bar test pattern
        // 3: Fade-to-gray color bar test pattern
        // 256: Walking 1s test pattern (12 bit)
//        _imgI2CWrite(0x3070, 0x0000);  // Normal operation (default)
//        _imgI2CWrite(0x3070, 0x0001);  // Solid color
//        _imgI2CWrite(0x3070, 0x0002);  // Color bars
//        _imgI2CWrite(0x3070, 0x0003);  // Fade-to-gray
//        _imgI2CWrite(0x3070, 0x0100);  // Walking 1s
    }
    
    // Set serial_format
    // *** This register write is necessary for parallel mode.
    // *** The datasheet doesn't mention this. :(
    // *** Discovered looking at Linux kernel source.
    {
        _imgI2CWrite(0x31AE, 0x0301);
    }
    
    // Set data_format_bits
    // Datasheet:
    //   "The serial format should be configured using R0x31AC.
    //   This register should be programmed to 0x0C0C when
    //   using the parallel interface."
    {
        _imgI2CWrite(0x31AC, 0x0C0C);
    }
    
    // Set row_speed
    {
//        _imgI2CWrite(0x3028, 0x0000);  // 0 cycle delay
//        _imgI2CWrite(0x3028, 0x0010);  // 1/2 cycle delay (default)
    }

    // Set the x-start address
    {
//        _imgI2CWrite(0x3004, 0x0006);  // Default
//        _imgI2CWrite(0x3004, 0x0010);
    }

    // Set the x-end address
    {
//        _imgI2CWrite(0x3008, 0x0905);  // Default
//        _imgI2CWrite(0x3008, 0x01B1);
    }

    // Set the y-start address
    {
//        _imgI2CWrite(0x3002, 0x007C);  // Default
//        _imgI2CWrite(0x3002, 0x007C);
    }

    // Set the y-end address
    {
//        _imgI2CWrite(0x3006, 0x058b);  // Default
//        _imgI2CWrite(0x3006, 0x016B);
    }
    
    // Implement "Recommended Default Register Changes and Sequencer"
    {
        _imgI2CWrite(0x3ED2, 0x0146);
        _imgI2CWrite(0x3EDA, 0x88BC);
        _imgI2CWrite(0x3EDC, 0xAA63);
        _imgI2CWrite(0x305E, 0x00A0);
    }
    
    // Enable/disable embedded_data (2 extra rows of statistical info)
    // See AR0134_RR_D.pdf for info on statistics format
    {
//            _imgI2CWrite(0x3064, 0x1902);  // Stats enabled (default)
        _imgI2CWrite(0x3064, 0x1802);  // Stats disabled
    }
    
    // Set coarse_integration_time
    {
        _imgI2CWrite(0x3012, 16384/8);
    }
    
    // Set fine_integration_time
    {
        _imgI2CWrite(0x3014, 0);
    }
    
    // Set analog_gain
    {
        _imgI2CWrite(0x3060, 63/8);
    }
}

void _imgSetStreamEnabled(bool en) {
    _imgI2CWrite(0x301A, (en ? 0x10DC : 0x10D8));
}

ImgCaptureStatusResp _imgCaptureStatus() {
    ImgCaptureStatusResp resp;
    _ice40Transfer(ImgCaptureStatusMsg(), resp);
    return resp;
}

void _imgCaptureImage() {
    _ice40Transfer(ImgCaptureMsg(0));
    
    // Wait for command to be sent
    const uint32_t MaxAttempts = 1000;
    for (uint32_t i=0;; i++) {
        Assert(i < MaxAttempts); // TODO: improve error handling
        if (i >= 10) _delayMs(1);
        auto status = _imgCaptureStatus();
        // Try again if the image hasn't been captured yet
        if (!status.done()) continue;
        return;
    }
    // Timeout capturing image
    // This should never happen, since it indicates a Verilog error or a hardware failure.
    abort();
}

void _iceInit() {
    _spiInit();
    
    // Confirm that we can communicate with the ICE40
    {
        const char str[] = "halla";
        EchoResp resp;
        _ice40Transfer(EchoMsg(str), resp);
        Assert(!memcmp((char*)resp.payload, str, sizeof(str)));
    }
}

int main() {
    // Init system (clock, pins, etc)
    _sysInit();
    // Init ICE40 comms
    _iceInit();
    // Initialize the image sensor
    _imgInit();
//    // Initialize the SD card
//    const uint16_t rca = _sdInit();
    // Enable image streaming
    _imgSetStreamEnabled(true);
    _ice40Transfer(LEDSetMsg(0x09));
    // Capture an image to RAM
    _imgCaptureImage();
//    // Write the image to the SD card
//    _sdWriteImage(rca);
    
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Off,  0, 1); // Disable SD clock, InitMode=enabled
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 0, 1); // SD clock = slow clock, InitMode=enabled
//        // <-- Turn on power to SD card
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 1, 1); // Trigger SDController init state machine
//        
//        // Wait 5ms
//        #5000000;
//        
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 0, 0); // SDController InitMode=disabled
    
    for (;;);
    
    return 0;
}
