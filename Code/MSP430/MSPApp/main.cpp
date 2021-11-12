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
using namespace GPIO;

static constexpr uint64_t MCLKFreqHz = 16000000;
static constexpr uint32_t XT1FreqHz = 32768;
static constexpr uint16_t SRSleepBits = GIE | LPM1_bits;

#define _sleepUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000)
#define _sleepMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000)

struct Pin {
    // Default GPIOs
    using VDD_1V9_IMG_EN                    = PortA::Pin<0x0, Option::Output0>;
    using VDD_2V8_IMG_EN                    = PortA::Pin<0x2, Option::Output0>;
    using ICE_MSP_SPI_DATA_DIR              = PortA::Pin<0x3>;
    using ICE_MSP_SPI_DATA_OUT              = PortA::Pin<0x4>;
    using ICE_MSP_SPI_DATA_IN               = PortA::Pin<0x5>;
    using ICE_MSP_SPI_CLK                   = PortA::Pin<0x6>;
    using ICE_MSP_SPI_AUX                   = PortA::Pin<0x7, Option::Output0>;
    using XOUT                              = PortA::Pin<0x8>;
    using XIN                               = PortA::Pin<0x9>;
    using ICE_MSP_SPI_AUX_DIR               = PortA::Pin<0xA, Option::Output1>;
    using VDD_SD_EN                         = PortA::Pin<0xB, Option::Output0>;
    using VDD_B_EN_                         = PortA::Pin<0xC, Option::Output1>;
    using MOTION_SIGNAL                     = PortA::Pin<0xD, Option::Interrupt01>;
    
    #warning remove
    using DEBUG_INT                         = PortA::Pin<0xC, Option::Interrupt01, Option::Resistor0>;
    using DEBUG_OUT                         = PortA::Pin<0xE, Option::Output0>;
};

using Clock = ClockType<XT1FreqHz, MCLKFreqHz, Pin::XOUT, Pin::XIN>;
using RTC = RTCType<XT1FreqHz>;
using SPI = SPIType<MCLKFreqHz, Pin::ICE_MSP_SPI_CLK, Pin::ICE_MSP_SPI_DATA_OUT, Pin::ICE_MSP_SPI_DATA_IN, Pin::ICE_MSP_SPI_DATA_DIR>;

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

static bool _Event = false;

__attribute__((interrupt(PORT2_VECTOR)))
void _isr_port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV__P2IFG5)) {
    case P2IV__P2IFG4:
        _Event = true;
        __bic_SR_register_on_exit(LPM3_bits);
        
//        for (;;) {
//            static bool a = 0;
//            Pin::DEBUG_OUT::Write(a);
//            _sleepMs(2);
//            a = !a;
//        }
        break;
    
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
    SPI::WriteRead(msg, resp);
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
    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
    PMMCTL0_L |= PMMREGOFF;
    
    // Go to sleep in LPM3.5
    __bis_SR_register(GIE | LPM3_bits);
}

#pragma mark - Main

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    PortA::Init<
        // SPI peripheral determines initial state of SPI GPIOs
        SPI::Pin::Clk,
        SPI::Pin::DataOut,
        SPI::Pin::DataIn,
        SPI::Pin::DataDir,
        // Clock peripheral determines initial state of clock GPIOs
        Clock::Pin::XOUT,
        Clock::Pin::XIN,
        
        Pin::DEBUG_INT,
        Pin::DEBUG_OUT
    >();
    
//    // Init GPIOs
//    GPIOInit<
//        Pin::VDD_1V9_IMG_EN,
//        Pin::VDD_2V8_IMG_EN,
//        Pin::ICE_MSP_SPI_DATA_DIR,
//        Pin::ICE_MSP_SPI_DATA_IN,
//        Pin::ICE_MSP_SPI_DATA_UCA0SOMI,
//        Pin::ICE_MSP_SPI_CLK_MANUAL,
//        Pin::ICE_MSP_SPI_AUX,
//        Pin::XOUT,
//        Pin::XIN,
//        Pin::ICE_MSP_SPI_AUX_DIR,
//        Pin::VDD_SD_EN,
//        Pin::VDD_B_EN_,
//        Pin::MOTION_SIGNAL
//    >();
    
    // Init clock
    Clock::Init();
    
//    // Init real-time clock
//    RTC::Init();
//    
//    // Init SPI
//    SPI::Init();
//    
//    // Init ICE40
//    ICE::Init();
    
//    // Enable interrupts
//    Toastbox::IRQState irq = Toastbox::IRQState::Enabled();
    
    // Check if we're waking from LPM3.5
    if (SYSRSTIV == SYSRSTIV__LPM5WU) {
        // Enable interrupts
//        Toastbox::IRQState irq = Toastbox::IRQState::Enabled();
        
        for (;;) {
            static bool a = 0;
            Pin::DEBUG_OUT::Write(a);
            _sleepMs(1);
            a = !a;
        }
//        __attribute__((section(".persistent")))
//        static int i = 0;
//        
//        ICE::Transfer(ICE::LEDSetMsg(i));
//        i++;
//        _sleep();
    }
    
    PAIFG = 0;
    
    Pin::DEBUG_OUT::Write(0);
    _sleepMs(5000);
    Pin::DEBUG_OUT::Write(1);
    
    _sleep();
    
    for (;;) {
        static bool a = 0;
        Pin::DEBUG_OUT::Write(a);
        _sleepMs(3);
        a = !a;
    }
    
    
//    for (int i=0;; i++) {
////        Toastbox::IRQState irq = Toastbox::IRQState::Disabled();
//        __bis_SR_register(GIE | LPM1_bits);
//        
//        ICE::Transfer(ICE::LEDSetMsg(i));
//    }
    
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
