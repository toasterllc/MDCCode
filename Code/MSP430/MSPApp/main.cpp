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
static constexpr uint16_t LPMBits = LPM3_bits;

#define _delayUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000)
#define _delayMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000)

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
};

using Clock = ClockType<XT1FreqHz, MCLKFreqHz, Pin::XOUT, Pin::XIN>;
using RTC = RTCType<XT1FreqHz>;
using SPI = SPIType<MCLKFreqHz, Pin::ICE_MSP_SPI_CLK, Pin::ICE_MSP_SPI_DATA_OUT, Pin::ICE_MSP_SPI_DATA_IN, Pin::ICE_MSP_SPI_DATA_DIR>;

SD::Card _sd;

#warning _imgAutoExp needs to be stored in FRAM
Img::AutoExposure _imgAutoExp;

#warning _imgDstIdx needs to be stored in FRAM
uint16_t _imgDstIdx = 0;

#pragma mark - Motion

static Img::Header _imgHeader = {
    // Section idx=0
    .version        = Img::HeaderVersion,
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
    // Initialize image sensor
    Img::Sensor::Init();
    
    // Initialize SD card
    _sd.init();
    
    // Enable image streaming
    Img::Sensor::SetStreamEnabled(true);
    
    // Set the initial exposure
    Img::Sensor::SetCoarseIntTime(_imgAutoExp.integrationTime());
    
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
}

#pragma mark - Interrupts

__attribute__((interrupt(RTC_VECTOR)))
static void _isr_rtc() {
    RTC::ISR();
}

static bool _Motion = false;

__attribute__((interrupt(PORT2_VECTOR)))
void _isr_port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV__P2IFG5)) {
    case P2IV__P2IFG5:
        _Motion = true;
        // Wake ourself
        __bic_SR_register_on_exit(LPMBits);
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
    _delayMs(2);
}

#pragma mark - Image Sensor

void Img::Sensor::SetPowerEnabled(bool en) {
    if (en) {
        Pin::VDD_2V8_IMG_EN::Write(1);
        _delayUs(100); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        Pin::VDD_1V9_IMG_EN::Write(1);
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        Pin::VDD_1V9_IMG_EN::Write(0);
        Pin::VDD_2V8_IMG_EN::Write(0);
    }
}

#pragma mark - IRQState

static bool _InterruptsEnabled() {
    return __get_SR_register() & GIE;
}

bool Toastbox::IRQState::SetInterruptsEnabled(bool en) {
    const bool prevEn = _InterruptsEnabled();
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
    return prevEn;
}

void Toastbox::IRQState::WaitForInterrupt() {
    // Put ourself to sleep until an interrupt occurs. This function may or may not return:
    // - This function returns if an interrupt was already pending and the ISR
    //   wakes us (via `__bic_SR_register_on_exit(LPMBits)`). In this case we
    //   never enter LPM3.5.
    // - This function doesn't return if an interrupt wasn't pending and
    //   therefore we enter LPM3.5. The next time we wake will be due to a
    //   reset and execution will start from main().
    
    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
    PMMCTL0_L |= PMMREGOFF;
    
    // Atomically enable interrupts and go to sleep
    const bool prevEn = _InterruptsEnabled();
    __bis_SR_register(GIE | LPMBits);
    // If interrupts were disabled previously, disable them again
    if (!prevEn) Toastbox::IRQState::SetInterruptsEnabled(false);
}

#pragma mark - Main

static void _sleep() {
    SD::Card::SetPowerEnabled(false);
    Img::Sensor::SetPowerEnabled(false);
    
    // Go to sleep
    Toastbox::IRQState::WaitForInterrupt();
}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    PortA::Init<
        // Power control
        Pin::VDD_1V9_IMG_EN,
        Pin::VDD_2V8_IMG_EN,
        Pin::VDD_SD_EN,
        Pin::VDD_B_EN_,
        
        // SPI peripheral determines initial state of SPI GPIOs
        SPI::Pin::Clk,
        SPI::Pin::DataOut,
        SPI::Pin::DataIn,
        SPI::Pin::DataDir,
        
        // Clock peripheral determines initial state of clock GPIOs
        Clock::Pin::XOUT,
        Clock::Pin::XIN,
        
        // Motion
        Pin::MOTION_SIGNAL,
        
        // Other
        Pin::ICE_MSP_SPI_AUX,
        Pin::ICE_MSP_SPI_AUX_DIR
    >();
    
    // Init clock
    Clock::Init();
    
    #warning do we want to reconfigure RTC when waking from LPM3.5?
    // Init real-time clock
    RTC::Init();
    
    #warning when waking due to only RTC, we don't need to initialize SPI or talk to ICE40. we just need to service the RTC int and go back to sleep
    
    // Init SPI
    SPI::Init();
    
    // Init ICE40
    ICE::Init();
    
    #warning TODO: keep the `SYSCFG0 = FRWPPW` or not? we need persistence for:
    #warning TODO: - image counter (in image header)
    #warning TODO: - image ring buffer write/read indexes
    #warning TODO: - RTC time (but we should put that in the backup RAM right?)
    // Enable FRAM writing
    SYSCFG0 = FRWPPW;
    
    {
        __attribute__((section(".persistent")))
        static int i = 0;
        ICE::Transfer(ICE::LEDSetMsg(i));
        i++;
    }
    
    // Enable interrupts
    Toastbox::IRQState irq = Toastbox::IRQState::Enabled();
    
    for (;;) {
        // Disable interrupts while we check for events
        Toastbox::IRQState irq = Toastbox::IRQState::Disabled();
        if (_Motion) {
            _Motion = false;
            // Enable ints while we handle motion
            irq.restore();
            
            _motion_handle();
            
        } else {
            // Go to sleep
            _sleep();
        }
    }
    
    return 0;
}

[[noreturn]] void abort() {
    for (;;);
}
