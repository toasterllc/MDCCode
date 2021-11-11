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
#include "Clock.h"
#include "RTC.h"
#include "SPI.h"
using namespace Toastbox;

static constexpr uint64_t MCLKFreqHz = 16000000;
static constexpr uint32_t XT1FreqHz = 32768;
static constexpr uint16_t SRSleepBits = GIE | LPM1_bits;

#define _sleepUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000)
#define _sleepMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000)

struct Pin {
    // Default GPIOs
    using VDD_1V9_IMG_EN                    = GPIOA<0x0, GPIOOption::Output0>;
    using VDD_2V8_IMG_EN                    = GPIOA<0x2, GPIOOption::Output0>;
    using ICE_MSP_SPI_DATA_DIR              = GPIOA<0x3, GPIOOption::Output1>;
    using ICE_MSP_SPI_DATA_IN               = GPIOA<0x4, GPIOOption::Input>;
    using ICE_MSP_SPI_DATA_UCA0SOMI         = GPIOA<0x5, GPIOOption::Sel01>;
    using ICE_MSP_SPI_CLK_MANUAL            = GPIOA<0x6, GPIOOption::Output1>;
    using ICE_MSP_SPI_AUX                   = GPIOA<0x7, GPIOOption::Output0>;
    using XOUT                              = GPIOA<0x8, GPIOOption::Sel10>;
    using XIN                               = GPIOA<0x9, GPIOOption::Sel10>;
    using ICE_MSP_SPI_AUX_DIR               = GPIOA<0xA, GPIOOption::Output1>;
    using VDD_SD_EN                         = GPIOA<0xB, GPIOOption::Output0>;
    using VDD_B_EN_                         = GPIOA<0xC, GPIOOption::Output1>;
    using MOTION_SIGNAL                     = GPIOA<0xD, GPIOOption::Input>;
//    using MOTION_SIGNAL                     = GPIOA<0xD, GPIOOption::Interrupt01>;
    
//    using DEBUG_OUT                         = GPIOA<0xE, GPIOOption::Output0>;
    
    // Alternate versions of above GPIOs
    using ICE_MSP_SPI_DATA_UCA0SIMO         = GPIOA<0x4, GPIOOption::Sel01>;
    using ICE_MSP_SPI_CLK_UCA0CLK           = GPIOA<0x6, GPIOOption::Sel01>;
};

using Clock = ClockType<XT1FreqHz, MCLKFreqHz>;
using RTC = RTCType<XT1FreqHz>;
using SPI = SPIType<MCLKFreqHz, Pin::ICE_MSP_SPI_CLK_MANUAL, Pin::ICE_MSP_SPI_CLK_UCA0CLK>;

SD::Card _sd;
Img::AutoExposure _imgAutoExp;
uint16_t _imgDstIdx = 0;

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
        _imgHeader.timestamp = RTC::CurrentTime();
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

__attribute__((interrupt(RTC_VECTOR)))
static void _isr_rtc() {
    RTC::ISR();
}

__attribute__((interrupt(PORT2_VECTOR)))
void _isr_port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV__P2IFG5)) {
    case P2IV__P2IFG5:
        // Wake ourself
        __bic_SR_register_on_exit(SRSleepBits);
        break;
    
    default:
        break;
    }
}

#pragma mark - ICE40

void ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & ICE::MsgType::Resp));
    
    // PA.4 = UCA0SIMO
    Pin::ICE_MSP_SPI_DATA_UCA0SIMO::Init();
    
    // PA.4 level shifter direction = MSP->ICE
    Pin::ICE_MSP_SPI_DATA_DIR::Write(1);
    
    SPI::TxRx(msg.type);
    
    for (uint8_t b : msg.payload) {
        SPI::TxRx(b);
    }
    
    // PA.4 = GPIO input
    Pin::ICE_MSP_SPI_DATA_IN::Init();
    
    // PA.4 level shifter direction = MSP<-ICE
    Pin::ICE_MSP_SPI_DATA_DIR::Write(0);
    
    // 8-cycle turnaround
    SPI::TxRx(0);
    
    // Clock in the response
    if (resp) {
        for (uint8_t& b : resp->payload) {
            b = SPI::TxRx(0);
        }
    }
}

#pragma mark - SD Card

const uint8_t SD::Card::ClkDelaySlow = 7;
const uint8_t SD::Card::ClkDelayFast = 0;

void SD::Card::SetPowerEnabled(bool en) {
    Pin::VDD_SD_EN::Write(en);
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _sleepMs(2);
}

#pragma mark - Image Sensor

void Img::Sensor::SetPowerEnabled(bool en) {
    if (en) {
        Pin::VDD_2V8_IMG_EN::Write(1);
        _sleepUs(100); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        Pin::VDD_1V9_IMG_EN::Write(1);
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        Pin::VDD_1V9_IMG_EN::Write(0);
        Pin::VDD_2V8_IMG_EN::Write(0);
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

static void _sleep() {
    // Ensure that interrupts are enabled before going to sleep:
    // > It is not possible to wake up from a port interrupt if its respective
    // > port interrupt flag is already asserted. TI recommends clearing the
    // > flags before entering LPMx.5. TI also recommends setting GIE = 1
    // > before entry into LPMx.5. This allows any pending flags to be serviced
    // > before LPMx.5 entry.
    Toastbox::IRQState irq = Toastbox::IRQState::Enabled();
    
    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
    PMMCTL0_L |= PMMREGOFF;
    
    // Go to sleep in LPM3.5
    __bis_SR_register(LPM3_bits);
}

#pragma mark - Main

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIOInit<
        Pin::VDD_1V9_IMG_EN,
        Pin::VDD_2V8_IMG_EN,
        Pin::ICE_MSP_SPI_DATA_DIR,
        Pin::ICE_MSP_SPI_DATA_IN,
        Pin::ICE_MSP_SPI_DATA_UCA0SOMI,
        Pin::ICE_MSP_SPI_CLK_MANUAL,
        Pin::ICE_MSP_SPI_AUX,
        Pin::XOUT,
        Pin::XIN,
        Pin::ICE_MSP_SPI_AUX_DIR,
        Pin::VDD_SD_EN,
        Pin::VDD_B_EN_,
        Pin::MOTION_SIGNAL
    >();
    
    // Init clock
    Clock::Init();
    
    // Init real-time clock
    RTC::Init();
    
    // Init SPI
    SPI::Init();
    
    // Init ICE40
    ICE::Init();
    
    // Enable interrupts
    Toastbox::IRQState irq = Toastbox::IRQState::Enabled();
    
    // Check if we're waking from LPM3.5
    if (SYSRSTIV == SYSRSTIV__LPM5WU) {
        __attribute__((section(".persistent")))
        static int i = 0;
        
        ICE::Transfer(ICE::LEDSetMsg(i));
        i++;
        _sleep();
    
    } else {
        
    }
    
    for (int i=0;; i++) {
//        Toastbox::IRQState irq = Toastbox::IRQState::Disabled();
        __bis_SR_register(GIE | LPM1_bits);
        
        ICE::Transfer(ICE::LEDSetMsg(i));
    }
    
//    // Initialize image sensor
//    Img::Sensor::Init();
//    
//    // Initialize SD card
//    _sd.init();
//    
//    // Enable image streaming
//    Img::Sensor::SetStreamEnabled(true);
//    
//    // Set the initial exposure
//    Img::Sensor::SetCoarseIntTime(_imgAutoExp.integrationTime());
//    
//    for (;;) {
//        // Go to sleep until we detect motion
//        IRQState::WaitForInterrupt();
//        
//        // We woke up
//        _motion_handle();
//    }
    
    return 0;
}
