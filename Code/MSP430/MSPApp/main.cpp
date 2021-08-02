#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "ICE40.h"
using namespace ICE40;
using SDRespTypes = ICE40::SDSendCmdMsg::RespTypes;
using SDDatInTypes = ICE40::SDSendCmdMsg::DatInTypes;

constexpr uint64_t MCLKFreqHz = 16000000;

#define _delay(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000);

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
    // Reset the ICE40 SPI state machine by asserting ice_msp_spi_clk for 10us
    {
        constexpr uint64_t ICE40SPIResetDurationUs = 10;
        
        // PA.6 = GPIO output
        PAOUT  &= ~BIT6;
        PADIR  |=  BIT6;
        PASEL1 &= ~BIT6;
        PASEL0 &= ~BIT6;
        
        PAOUT  |=  BIT6;
        _delay(ICE40SPIResetDurationUs);
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

static void _spiTxRx(const ICE40::Msg& msg, ICE40::Resp& resp) {
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

template <typename T>
static T _ice40Transfer(const ICE40::Msg& msg) {
    T resp;
    _spiTxRx(msg, resp);
    return resp;
}

static void _ice40Transfer(const ICE40::Msg& msg) {
    _ice40Transfer<ICE40::Resp>(msg);
}

SDGetStatusResp _sdGetStatus() {
    return _ice40Transfer<SDGetStatusResp>(SDGetStatusMsg());
}

SDGetStatusResp _sdSendCmd(
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
        if (i >= 10) _delay(1000);
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

int main() {
    _sysInit();
    _spiInit();
    
//    for (uint8_t i=0;; i++) {
//        
//        {
//            const char msgStr[] = "halla";
//            const ICE40::EchoMsg msg(msgStr);
//            ICE40::EchoResp resp;
//            txrx(msg, resp);
//            if (memcmp(msg.payload, resp.payload+1, sizeof(msgStr))) {
//                const ICE40::LEDSetMsg msg(i);
//                txrx(msg);
//            }
//        }
//        
//        __delay_cycles(1600000);
//    }
    
//    volatile bool go = false;
//    while (!go);
    
    const uint8_t SDClkDelaySlow = 15;
    const uint8_t SDClkDelayFast = 2;
    
    // Confirm that we can communicate with the ICE40
    {
        char str[] = "halla";
        auto status = _ice40Transfer<EchoResp>(EchoMsg(str));
        Assert(!strcmp((char*)status.payload, str));
    }
    
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Off,  0, 1); // Disable SD clock, InitMode=enabled
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 0, 1); // SD clock = slow clock, InitMode=enabled
//        // <-- Turn on power to SD card
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 1, 1); // Trigger SDController init state machine
//        
//        // Wait 5ms
//        #5000000;
//        
//        TestSDConfig(0, `Msg_Arg_SDInit_Clk_Speed_Slow, 0, 0); // SDController InitMode=disabled
    
    // Disable SD power
    _sdSetPowerEnabled(false);
    _delay(100000);
    // InitMode=enabled, Clock=off
    _ice40Transfer(SDInitMsg(SDInitMsg::State::Enabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Off, SDClkDelaySlow));
    // SD clock = slow clock
    _ice40Transfer(SDInitMsg(SDInitMsg::State::Enabled, SDInitMsg::Trigger::Nop, SDInitMsg::ClkSpeed::Slow, SDClkDelaySlow));
    // Turn on SD card power
    _sdSetPowerEnabled(true);
    // Trigger the SD card low voltage signalling (LVS) init sequence
    _ice40Transfer(SDInitMsg(SDInitMsg::State::Enabled, SDInitMsg::Trigger::Trigger, SDInitMsg::ClkSpeed::Slow, SDClkDelaySlow));
    // Wait 5ms for the LVS init sequence to complete
    _delay(5000);
    // Disable SDController init mode
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
//        SendMsg(`Msg_Type_SDGetStatus, 0);
//        // We're done when the `InitDone` bit is set
//        done = spi_resp[`Resp_Arg_SDGetStatus_InitDone_Bits];
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
        Assert(!status.sdRespCRCErr());
        const uint8_t replyVoltage = status.sdRespGetBits(19,16);
        Assert(replyVoltage == Voltage);
        const uint8_t replyCheckPattern = status.sdRespGetBits(15,8);
        Assert(replyCheckPattern == CheckPattern);
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
//            Assert(!status.sdRespCRCErr());
//        }
//        
//        // CMD41
//        {
//            auto status = _sdSendCmd(41, 0x51008000);
//            // Don't check CRC with .sdRespCRCOK() (the CRC response to ACMD41 is all 1's)
//            Assert(status.sdRespGetBits(45,40) == 0x3F); // Command should be 6'b111111
//            Assert(status.sdRespGetBits(7,1) == 0x7F); // CRC should be 7'b1111111
//            // Check if card is ready. If it's not, retry ACMD41.
//            if (!status.sdRespGetBit(39)) continue;
//            // Check if we can switch to 1.8V
//            // If not, we'll assume we're already in 1.8V mode
//            switchTo1V8 = status.sdRespGetBit(32);
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
//            Assert(!status.sdRespCRCErr());
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
//                auto status = _sdGetStatus();
//                if (status.sdDat0Idle()) break;
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
//        Assert(!status.sdRespCRCErr());
//        // Get the card's RCA from the response
//        rca = status.sdRespGetBits(39,24);
//    }
//    
//    // ====================
//    // CMD7 | SELECT_CARD/DESELECT_CARD
//    //   State: Standby -> Transfer
//    //   Select card
//    // ====================
//    {
//        auto status = _sdSendCmd(7, ((uint32_t)rca)<<16);
//        Assert(!status.sdRespCRCErr());
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
//            Assert(!status.sdRespCRCErr());
//        }
//        
//        // CMD6
//        {
//            auto status = _sdSendCmd(6, 0x00000002);
//            Assert(!status.sdRespCRCErr());
//        }
//    }
//    
//    // ====================
//    // CMD6 | SWITCH_FUNC
//    //   State: Transfer -> Data
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
//        Assert(!status.sdRespCRCErr());
//        Assert(!status.sdDatInCRCErr());
//        // Verify that the access mode was successfully changed
//        // TODO: properly handle this failing, see CMD6 docs
//        Assert(status.sdDatInCMD6AccessMode() == 0x03);
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
//                Assert(!status.sdRespCRCErr());
//            }
//            
//            // CMD23
//            {
//                auto status = _sdSendCmd(23, 0x00000001);
//                Assert(!status.sdRespCRCErr());
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
//            Assert(!status.sdRespCRCErr());
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
//                auto status = _sdGetStatus();
//                if (status.sdDatOutDone()) {
//                    if (status.sdDatOutCRCErr()) {
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
//            Assert(!status.sdRespCRCErr());
//            
//            // Wait for SD card to indicate that it's ready (DAT0=1)
//            for (;;) {
//                if (status.sdDat0Idle()) break;
//                status = _sdGetStatus();
//            }
//        }
//        
//        _led0.write(on);
//        on = !on;
//    }

    for (;;);
    
    return 0;
}
