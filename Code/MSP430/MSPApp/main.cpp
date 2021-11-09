#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "SDCard.h"
#include "ICE.h"
#include "ImgSensor.h"
#include "ImgAutoExposure.h"

constexpr uint64_t MCLKFreqHz = 16000000;

#define _sleepUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000)
#define _sleepMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000)

#pragma mark - System

static void _clock_init() {
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

static void _spi_init() {
    // Reset the ICE40 SPI state machine by asserting ice_msp_spi_clk for some period
    {
        constexpr uint64_t ICE40SPIResetDurationUs = 18;
        
        // PA.6 = GPIO output
        PAOUT  &= ~BIT6;
        PADIR  |=  BIT6;
        PASEL1 &= ~BIT6;
        PASEL0 &= ~BIT6;
        
        PAOUT  |=  BIT6;
        _sleepUs(ICE40SPIResetDurationUs);
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

static uint8_t _spi_txrx(uint8_t b) {
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

static void _sys_init() {
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
        _clock_init();
    }
    
    // Unlock GPIOs
    {
        PM5CTL0 &= ~LOCKLPM5;
    }
    
    // Initialize SPI
    {
        _spi_init();
    }
}

#pragma mark - ICE40

void ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & ICE::MsgType::Resp));
    
    // PA.4 = UCA0SIMO
    PASEL1 &= ~BIT4;
    PASEL0 |=  BIT4;
    
    // PA.4 level shifter direction = MSP->ICE
    PAOUT |= BIT3;
    
    _spi_txrx(msg.type);
    
    for (uint8_t b : msg.payload) {
        _spi_txrx(b);
    }
    
    // PA.4 = GPIO input
    PASEL1 &= ~BIT4;
    PASEL0 &= ~BIT4;
    
    // PA.4 level shifter direction = MSP<-ICE
    PAOUT &= ~BIT3;
    
    // 8-cycle turnaround
    _spi_txrx(0);
    
    // Clock in the response
    if (resp) {
        for (uint8_t& b : resp->payload) {
            b = _spi_txrx(0);
        }
    }
}

#pragma mark - SD Card

SD::Card _sd;
const uint8_t SD::Card::ClkDelaySlow = 7;
const uint8_t SD::Card::ClkDelayFast = 0;

void SD::Card::SetPowerEnabled(bool en) {
    constexpr uint16_t VDD_SD_EN = BITB;
    if (en) {
        PADIR |=  VDD_SD_EN;
        PAOUT |=  VDD_SD_EN;
    } else {
        PADIR |=  VDD_SD_EN;
        PAOUT &= ~VDD_SD_EN;
    }
    
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _sleepMs(2);
}

#pragma mark - Image Sensor

void Img::Sensor::SetPowerEnabled(bool en) {
    constexpr uint16_t VDD_1V9_IMG_EN = BIT0;
    constexpr uint16_t VDD_2V8_IMG_EN = BIT2;
    PADIR |=  VDD_2V8_IMG_EN|VDD_1V9_IMG_EN;
    
    if (en) {
        PAOUT |=  VDD_2V8_IMG_EN;
        _sleepUs(100); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        PAOUT |=  VDD_1V9_IMG_EN;
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        PAOUT &= ~(VDD_2V8_IMG_EN|VDD_1V9_IMG_EN);
    }
}

#pragma mark - Main

Img::AutoExposure _imgAutoExp;

int main() {
    // Init system (clock, pins, etc)
    _sys_init();
    // Init ICE40
    ICE::Init();
    // Initialize image sensor
    Img::Sensor::Init();
    // Initialize SD card
    _sd.init();
    // Enable image streaming
    Img::Sensor::SetStreamEnabled(true);
    
    // Set exposure to the last exposure that we used
    Img::Sensor::SetCoarseIntTime(_imgAutoExp.integrationTime());
    
    for (int i=0; i<10; i++) {
        ICE::Transfer(ICE::LEDSetMsg(i));
        
        // Try up to `CaptureAttemptCount` times to capture a properly-exposed image
        constexpr uint8_t CaptureAttemptCount = 3;
        uint8_t bestExpBlock = 0;
        uint8_t bestExpScore = 0;
        for (uint8_t i=0; i<CaptureAttemptCount; i++) {
//            // skipCount:
//            // On the initial capture, we didn't set the exposure, so we don't need to skip any images.
//            // On subsequent captures, we did set the exposure before the capture, so we need to skip a single
//            // image since the first image after setting the exposure is invalid.
//            const uint8_t skipCount = (!i ? 0 : 1);
            constexpr uint8_t SkipCount = 1;
            
            // expBlock: Store images in the block belonging to the worst-exposed image captured so far
            const uint8_t expBlock = !bestExpBlock;
            
            // Capture an image to RAM
            bool ok = false;
            ICE::ImgCaptureStatusResp resp;
            std::tie(ok, resp) = ICE::ImgCapture(expBlock, SkipCount);
            Assert(ok);
            
            const uint8_t expScore = _imgAutoExp.update(resp.highlightCount(), resp.shadowCount());
            if (!bestExpScore || (expScore > bestExpScore)) {
                bestExpBlock = expBlock;
                bestExpScore = expScore;
            }
            
            // We're done if we don't have any exposure changes
            if (!_imgAutoExp.changed()) break;
            
            // Update the exposure
            Img::Sensor::SetCoarseIntTime(_imgAutoExp.integrationTime());
        }
        
        // Write the best-exposed image to the SD card
        _sd.writeImage(bestExpBlock, i);
        _sleepMs(500);
    }
    
    for (;;);
    
    return 0;
}
