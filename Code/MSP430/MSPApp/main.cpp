#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "SDCard.h"
#include "ICE.h"
#include "ImgSensor.h"
#include "ImgAutoExposure.h"
#include "Toastbox/IRQState.h"
#include "GPIO.h"
using namespace Toastbox;

constexpr uint64_t MCLKFreqHz = 16000000;
constexpr uint16_t SRSleepBits = GIE | LPM1_bits;

#define _sleepUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000)
#define _sleepMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000)

// Default GPIOs
using GPIO_VDD_1V9_IMG_EN                   = GPIOA<0x0, GPIOOption::Dir>;
using GPIO_VDD_2V8_IMG_EN                   = GPIOA<0x2, GPIOOption::Dir>;
using GPIO_ICE_MSP_SPI_DATA_DIR             = GPIOA<0x3, GPIOOption::Dir>;
using GPIO_ICE_MSP_SPI_DATA_IN              = GPIOA<0x4>;
using GPIO_ICE_MSP_SPI_DATA_UCA0SOMI        = GPIOA<0x5, GPIOOption::Sel0>;
using GPIO_ICE_MSP_SPI_CLK_MANUAL           = GPIOA<0x6, GPIOOption::Out, GPIOOption::Dir>;
using GPIO_ICE_MSP_SPI_AUX                  = GPIOA<0x7, GPIOOption::Dir>;
using GPIO_XOUT                             = GPIOA<0x8, GPIOOption::Sel1>;
using GPIO_XIN                              = GPIOA<0x9, GPIOOption::Sel1>;
using GPIO_ICE_MSP_SPI_AUX_DIR              = GPIOA<0xA, GPIOOption::Out, GPIOOption::Dir>;
using GPIO_VDD_SD_EN                        = GPIOA<0xB, GPIOOption::Dir>;
using GPIO_VDD_B_EN_                        = GPIOA<0xC, GPIOOption::Out, GPIOOption::Dir>;
using GPIO_MOTION_SIGNAL                    = GPIOA<0xD, GPIOOption::IE>;

// Alternate versions of above GPIOs
using GPIO_ICE_MSP_SPI_DATA_UCA0SIMO        = GPIOA<0x4, GPIOOption::Sel0>;
using GPIO_ICE_MSP_SPI_CLK_UCA0CLK          = GPIOA<0x6, GPIOOption::Sel0>;

SD::Card _sd;
Img::AutoExposure _imgAutoExp;
uint16_t _imgDstIdx = 0;

#pragma mark - Clock

static void _clock_init() {
    constexpr uint32_t XT1FreqHz = 32768;
    
    // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
    // This must happen before configuring the clock system.
    FRCTL0 = FRCTLPW | NWAITS_1;
    
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

#pragma mark - SPI

static void _spi_init() {
    // Reset the ICE40 SPI state machine by asserting ICE_MSP_SPI_CLK for some period
    {
        constexpr uint64_t ICE40SPIResetDurationUs = 18;
        GPIO_ICE_MSP_SPI_CLK_MANUAL::Out(1);
        _sleepUs(ICE40SPIResetDurationUs);
        GPIO_ICE_MSP_SPI_CLK_MANUAL::Out(0);
    }
    
    // Configure SPI peripheral
    {
        // Turn over control of ICE_MSP_SPI_CLK to the SPI peripheral (PA.6 = UCA0CLK)
        GPIO_ICE_MSP_SPI_CLK_UCA0CLK::Init();
        
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

#pragma mark - Motion

static constexpr uint16_t ImgHeaderVersion = 0x4242;

static Img::Header _imgHeader = {
    // Section idx=0
    .version        = ImgHeaderVersion,
    .imageWidth     = Img::PixelWidth,
    .imageHeight    = Img::PixelHeight,
    ._pad0          = 0,
    // Section idx=1
    .counter        = 0,
    ._pad1          = 0,
    // Section idx=2
    .timestamp      = 0,
    ._pad2          = 0,
    // Section idx=3
    .coarseIntTime  = 0,
    .analogGain     = 0,
    ._pad3          = 0,
};

static void _motion_handle() {
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
        
        // Update the header
        _imgHeader.coarseIntTime = _imgAutoExp.integrationTime();
        
        // Capture an image to RAM
        bool ok = false;
        ICE::ImgCaptureStatusResp resp;
        std::tie(ok, resp) = ICE::ImgCapture(_imgHeader, expBlock, SkipCount);
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
    _sd.writeImage(bestExpBlock, _imgDstIdx);
    _imgDstIdx++;
    
    // Update the image counter
    _imgHeader.counter++;
    
    ICE::Transfer(ICE::LEDSetMsg(_imgDstIdx));
}

#pragma mark - Interrupts

__interrupt __attribute__((interrupt(PORT2_VECTOR)))
void _isr_port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt,
    // so we don't have to clear bits in P2IFG manually.
    // If there are multiple interrupts pending, then this ISR is called
    // multiple times.
    switch (__even_in_range(P2IV, P2IV__P2IFG7)) {
    case P2IV__P2IFG5:
        // Wake ourself
        __bic_SR_register_on_exit(SRSleepBits);
        break;
    default:
        break;
    }
}

static void _sys_init() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIOInit<
        GPIO_VDD_1V9_IMG_EN,
        GPIO_VDD_2V8_IMG_EN,
        GPIO_ICE_MSP_SPI_DATA_DIR,
        GPIO_ICE_MSP_SPI_DATA_IN,
        GPIO_ICE_MSP_SPI_DATA_UCA0SOMI,
        GPIO_ICE_MSP_SPI_CLK_MANUAL,
        GPIO_ICE_MSP_SPI_AUX,
        GPIO_XOUT,
        GPIO_XIN,
        GPIO_ICE_MSP_SPI_AUX_DIR,
        GPIO_VDD_SD_EN,
        GPIO_VDD_B_EN_,
        GPIO_MOTION_SIGNAL
    >();
    
    // Configure clock system
    _clock_init();
    
    // Init SPI
    _spi_init();
}

#pragma mark - ICE40

void ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & ICE::MsgType::Resp));
    
    GPIO_ICE_MSP_SPI_DATA_UCA0SIMO::Init();
    
    // PA.4 level shifter direction = MSP->ICE
    GPIO_ICE_MSP_SPI_DATA_DIR::Out(1);
    
    _spi_txrx(msg.type);
    
    for (uint8_t b : msg.payload) {
        _spi_txrx(b);
    }
    
    // PA.4 = GPIO input
    GPIO_ICE_MSP_SPI_DATA_IN::Init();
    
    // PA.4 level shifter direction = MSP<-ICE
    GPIO_ICE_MSP_SPI_DATA_DIR::Out(0);
    
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

const uint8_t SD::Card::ClkDelaySlow = 7;
const uint8_t SD::Card::ClkDelayFast = 0;

void SD::Card::SetPowerEnabled(bool en) {
    GPIO_VDD_SD_EN::Out(en);
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _sleepMs(2);
}

#pragma mark - Image Sensor

void Img::Sensor::SetPowerEnabled(bool en) {
    if (en) {
        GPIO_VDD_2V8_IMG_EN::Out(1);
        _sleepUs(100); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        GPIO_VDD_1V9_IMG_EN::Out(1);
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        GPIO_VDD_1V9_IMG_EN::Out(0);
        GPIO_VDD_2V8_IMG_EN::Out(0);
    }
}

#pragma mark - IRQState

bool Toastbox::IRQState::SetInterruptsEnabled(bool en) {
    const bool prevEn = __get_SR_register() & GIE;
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
    return prevEn;
}

void Toastbox::IRQState::WaitForInterrupt() {
    // Go to sleep
    __bis_SR_register(SRSleepBits);
}

#pragma mark - Main

int main() {
    // Init system (clock, pins, etc)
    _sys_init();
    
    // Init ICE40
    ICE::Init();
    
//    for (int i=0;; i++) {
//        ICE::Transfer(ICE::LEDSetMsg(i));
//        _sleepMs(500);
//    }
    
    // Initialize image sensor
    Img::Sensor::Init();
    
    // Initialize SD card
    _sd.init();
    
    // Enable image streaming
    Img::Sensor::SetStreamEnabled(true);
    
    // Set the initial exposure
    Img::Sensor::SetCoarseIntTime(_imgAutoExp.integrationTime());
    
    for (;;) {
        // Go to sleep until we detect motion
        IRQState::WaitForInterrupt();
        
        // We woke up
        _motion_handle();
    }
    
    return 0;
}
