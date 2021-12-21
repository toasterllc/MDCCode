#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#define TaskMSP430
#include "Toastbox/Task.h"
#include "SDCard.h"
#include "ICE.h"
#include "ImgSensor.h"
#include "ImgAutoExposure.h"
#include "Startup.h"
#include "GPIO.h"
#include "Clock.h"
#include "RTC.h"
#include "SPI.h"
#include "WDT.h"
#include "FRAMWriteEn.h"
#include "Util.h"
#include "Toastbox/IntState.h"
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz   = 16000000;
static constexpr uint32_t _XT1FreqHz    = 32768;
static constexpr uint32_t _WDTPeriodUs  = 512;

struct _Pin {
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
    using MOTION_SIGNAL                     = PortA::Pin<0xD, Option::Resistor0, Option::Interrupt01>; // Motion sensor can only pull up, so it requires a pulldown resistor
    
    using DEBUG_OUT                         = PortA::Pin<0xE, Option::Output0>;
};

using _Clock = ClockType<_XT1FreqHz, _MCLKFreqHz, _Pin::XOUT, _Pin::XIN>;
using _WDT = WDTType<_MCLKFreqHz, _WDTPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN, _Pin::ICE_MSP_SPI_DATA_DIR>;

class _MotionTask;
class _SDTask;
class _ImgTask;
class _BusyTimeoutTask;

using _Scheduler = Toastbox::Scheduler<
    _WDTPeriodUs,       // T_UsPerTick: microseconds per tick
    nullptr,            // T_MainStack: main stack pointer
    0,                  // T_StackGuardSize: number of stack guards to use
    _MotionTask,        // T_Tasks
    _SDTask,
    _ImgTask,
    _BusyTimeoutTask
>;

using _ICE = ICE<
    _Scheduler
>;

static void _SDSetPowerEnabled(bool en);
static void _ImgSetPowerEnabled(bool en);

using _ImgSensor = Img::Sensor<
    _Scheduler,             // T_Scheduler
    _ICE,                   // T_ICE
    _ImgSetPowerEnabled     // T_SetPowerEnabled
>;

using _SDCard = SD::Card<
    _Scheduler,         // T_Scheduler
    _ICE,               // T_ICE
    _SDSetPowerEnabled, // T_SetPowerEnabled
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    0                   // T_ClkDelayFast (odd values invert the clock)
>;

// _StartTime: the time set by STM32 (seconds since reference date)
// Stored in 'Information Memory' (FRAM) because it needs to persist across a cold start.
[[gnu::section(".fram_info.main")]]
static volatile struct {
    uint32_t time   = 0;
    uint16_t valid  = false; // uint16_t (instead of bool) for alignment
} _StartTime;

// _RTC: real time clock
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
[[gnu::section(".ram_backup.main")]]
static RTC<_XT1FreqHz> _RTC;

// _ImgAutoExp: auto exposure algorithm object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
[[gnu::section(".ram_backup.main")]]
static Img::AutoExposure _ImgAutoExp;

// _ImgIndexes: stats to track captured images
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely.
[[gnu::section(".fram_info.main")]]
static volatile struct {
    uint32_t counter = 0;
    uint16_t write = 0;
    uint16_t read = 0;
    bool full = false;
} _ImgIndexes;

struct _SDTask {
    static void Enable() {
        Wait();
        _Scheduler::Start<_SDTask>(_SDCard::Enable);
    }
    
    static void Disable() {
        Wait();
        _Scheduler::Start<_SDTask>(_SDCard::Disable);
    }
    
    static void Wait() {
        _Scheduler::Wait<_SDTask>();
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._SDTask")]]
    static inline uint8_t Stack[128];
};

struct _ImgTask {
    static void Enable() {
        Wait();
        _Scheduler::Start<_ImgTask>([] {
            // Initialize image sensor
            _ImgSensor::Enable();
            // Set the initial exposure _before_ we enable streaming, so that the very first frame
            // has the correct exposure, so we don't have to skip any frames on the first capture.
            _ImgSensor::SetCoarseIntTime(_ImgAutoExp.integrationTime());
            // Enable image streaming
            _ImgSensor::SetStreamEnabled(true);
        });
    }
    
    static void Disable() {
        Wait();
        _Scheduler::Start<_ImgTask>(_ImgSensor::Disable);
    }
    
    static void Wait() {
        _Scheduler::Wait<_ImgTask>();
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._ImgTask")]]
    static inline uint8_t Stack[128];
};

// MARK: - Motion

static volatile bool _Motion = false;
static volatile bool _Busy = false;

static void _CaptureImage() {
    // Asynchronously turn on the image sensor / SD card
    _ImgTask::Enable();
    _SDTask::Enable();
    
    // Wait until the image sensor is ready
    _ImgTask::Wait();
    
    // Try up to `CaptureAttemptCount` times to capture a properly-exposed image
    constexpr uint8_t CaptureAttemptCount = 3;
    uint8_t bestExpBlock = 0;
    uint8_t bestExpScore = 0;
    for (uint8_t i=0; i<CaptureAttemptCount; i++) {
        // skipCount:
        // On the initial capture, we didn't set the exposure, so we don't need to skip any images.
        // On subsequent captures, we did set the exposure before the capture, so we need to skip a single
        // image since the first image after setting the exposure is invalid.
        const uint8_t skipCount = (!i ? 0 : 1);
        
        // expBlock: Store images in the block belonging to the worst-exposed image captured so far
        const uint8_t expBlock = !bestExpBlock;
        
        // Populate the header
        static Img::Header header = {
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
        
        header.counter = _ImgIndexes.counter;
        header.timestamp = _RTC.currentTime();
        header.coarseIntTime = _ImgAutoExp.integrationTime();
        
        // Capture an image to RAM
        const _ICE::ImgCaptureStatusResp resp = _ICE::ImgCapture(header, expBlock, skipCount);
        const uint8_t expScore = _ImgAutoExp.update(resp.highlightCount(), resp.shadowCount());
        if (!bestExpScore || (expScore > bestExpScore)) {
            bestExpBlock = expBlock;
            bestExpScore = expScore;
        }
        
        // We're done if we don't have any exposure changes
        if (!_ImgAutoExp.changed()) break;
        
        // Update the exposure
        _ImgSensor::SetCoarseIntTime(_ImgAutoExp.integrationTime());
    }
    
    // Wait until the SD card is ready
    _SDTask::Wait();
    
    // Write the best-exposed image to the SD card
    _SDCard::WriteImage(bestExpBlock, _ImgIndexes.write);
    
    // Update _ImgIndexes
    {
        FRAMWriteEn writeEn; // Enable FRAM writing
        _ImgIndexes.write++;
        _ImgIndexes.counter++;
    }
}

// MARK: - Interrupts

[[gnu::interrupt(RTC_VECTOR)]]
static void _ISR_RTC() {
    _RTC.isr();
}

[[gnu::interrupt(PORT2_VECTOR)]]
static void _ISR_Port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV__P2IFG5)) {
    case P2IV__P2IFG5:
        _Motion = true;
        // Wake ourself
        #warning figure out if we want to clear GIE here, especially wrt _Scheduler. don't think we do because we may just be running a task, and we don't want to change the interrupt state out from under it
        __bic_SR_register_on_exit(LPM3_bits);
        break;
    
    default:
        break;
    }
}

[[gnu::interrupt(WDT_VECTOR)]]
static void _ISR_WDT() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        #warning figure out if we want to clear GIE here, especially wrt _Scheduler. don't think we do because we may just be running a task, and we don't want to change the interrupt state out from under it
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

// MARK: - ICE40

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    
    static bool iceInit = false;
    // Init ICE40 if we haven't done so yet
    if (!iceInit) {
        iceInit = true;
        
        // Init SPI/ICE40
        if (Startup::ColdStart()) {
            constexpr bool iceReset = true; // Cold start -> reset ICE40 SPI state machine
            _SPI::Init(iceReset);
            _ICE::Init(); // Cold start -> init ICE40 to verify that comms are working
        
        } else {
            constexpr bool iceReset = false; // Warm start -> no need to reset ICE40 SPI state machine
            _SPI::Init(iceReset);
        }
    }
    
    _SPI::WriteRead(msg, resp);
}

// MARK: - SD Card

static void _SDSetPowerEnabled(bool en) {
    _Pin::VDD_SD_EN::Write(en);
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _Scheduler::SleepMs<2>();
}

// MARK: - Image Sensor

static void _ImgSetPowerEnabled(bool en) {
    if (en) {
        _Pin::VDD_2V8_IMG_EN::Write(1);
        _Scheduler::SleepUs<100>(); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
        _Pin::VDD_1V9_IMG_EN::Write(1);
        
        #warning measure actual delay that we need for the rails to rise
    
    } else {
        // No delay between 2V8/1V9 needed for power down (per AR0330CS datasheet)
        _Pin::VDD_1V9_IMG_EN::Write(0);
        _Pin::VDD_2V8_IMG_EN::Write(0);
        
        #warning measure actual delay that we need for the rails to fall
    }
}

// MARK: - IntState

inline bool Toastbox::IntState::InterruptsEnabled() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

void Toastbox::IntState::WaitForInterrupt() {
    // Put ourself to sleep until an interrupt occurs. This function may or may not return:
    // 
    // - This function returns if an interrupt was already pending and the ISR
    //   wakes us (via `__bic_SR_register_on_exit`). In this case we never enter LPM3.5.
    // 
    // - This function doesn't return if an interrupt wasn't pending and
    //   therefore we enter LPM3.5. The next time we wake will be due to a
    //   reset and execution will start from main().
    
    // If we're currently handling motion, enter LPM1 sleep because a task is just delaying itself.
    // If we're not handling motion, enter the deep LPM3.5 sleep, where RAM content is lost.
    const uint16_t LPMBits = (_Busy ? LPM1_bits : LPM3_bits);
//    const uint16_t LPMBits = LPM1_bits;
    
    // If we're entering LPM3, disable regulator so we enter LPM3.5 (instead of just LPM3)
    if (LPMBits == LPM3_bits) {
        PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
        PMMCTL0_L |= PMMREGOFF;
    }
    
    // Atomically enable interrupts and go to sleep
    const bool prevEn = Toastbox::IntState::InterruptsEnabled();
    __bis_SR_register(GIE | LPMBits);
    // If interrupts were disabled previously, disable them again
    if (!prevEn) Toastbox::IntState::SetInterruptsEnabled(false);
}

// MARK: - Tasks

//static void debugSignal() {
//    _Pin::DEBUG_OUT::Init();
//    for (int i=0; i<10; i++) {
//        _Pin::DEBUG_OUT::Write(0);
//        for (volatile int i=0; i<10000; i++);
//        _Pin::DEBUG_OUT::Write(1);
//        for (volatile int i=0; i<10000; i++);
//    }
//}

struct _BusyTimeoutTask {
    static void Run() {
        for (;;) {
            // Stay on for 1 second waiting for motion
            _Scheduler::SleepMs<1000>();
            
            // Asynchronously turn off the image sensor / SD card
            _ImgTask::Disable();
            _SDTask::Disable();
            
            // Wait until the image sensor / SD card are off
            _ImgTask::Wait();
            _SDTask::Wait();
            
            // Update our state
            _Busy = false;
        }
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<>;
    
    // Task stack
    [[gnu::section(".stack._BusyTimeoutTask")]]
    static inline uint8_t Stack[128];
};

struct _MotionTask {
    static void Run() {
        for (;;) {
            // Wait for motion
            _Scheduler::Wait([&] { return _Motion; });
            _Motion = false;
            _Busy = true;
            
            // Stop the timeout task while we capture a new image
            _Scheduler::Stop<_BusyTimeoutTask>();
            
            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
            
            // Capture an image
            _CaptureImage();
            
            _ICE::Transfer(_ICE::LEDSetMsg(0x00));
            
            // Restart the timeout task, so that we turn off automatically if
            // we're idle for a bit
            _Scheduler::Start<_BusyTimeoutTask>(_BusyTimeoutTask::Run);
        }
    }
    
    // Task options
    using Options = Toastbox::TaskOptions<
        Toastbox::TaskOption::AutoStart<Run> // Task should start running
    >;
    
    // Task stack
    [[gnu::section(".stack._MotionTask")]]
    static inline uint8_t Stack[128];
};

// MARK: - Main

#warning verify that _StackMainSize is large enough
#define _StackMainSize 128

[[gnu::section(".stack.main")]]
uint8_t _StackMain[_StackMainSize];

asm(".global __stack");
asm(".equ __stack, _StackMain+" Stringify(_StackMainSize));

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIO::Init<
        // Power control
        _Pin::VDD_1V9_IMG_EN,
        _Pin::VDD_2V8_IMG_EN,
        _Pin::VDD_SD_EN,
        _Pin::VDD_B_EN_,
        
        // SPI peripheral determines initial state of SPI GPIOs
        _SPI::Pin::Clk,
        _SPI::Pin::DataOut,
        _SPI::Pin::DataIn,
        _SPI::Pin::DataDir,
        
        // Clock peripheral determines initial state of clock GPIOs
        _Clock::Pin::XOUT,
        _Clock::Pin::XIN,
        
        // Motion
        _Pin::MOTION_SIGNAL,
        
        // Other
        _Pin::ICE_MSP_SPI_AUX,
        _Pin::ICE_MSP_SPI_AUX_DIR
    >();
    
    // Init clock
    _Clock::Init();
    
    #warning if this is a cold start:
    #warning   wait a few milliseconds to allow our outputs to settle so that our peripherals
    #warning   (SD card, image sensor) fully turn off, because we may have restarted because
    #warning   of an error
    
    #warning how do we handle turning off SD clock after an error occurs?
    #warning   ? don't worry about that because in the final design,
    #warning   we'll be powering off ICE40 anyway?
    
    if (Startup::ColdStart()) {
        // If we do have a valid startTime, consume _startTime and hand it off to _RTC.
        // Otherwise, initialize _RTC with 0. This will enable RTC, but it won't
        // enable the interrupt, so _RTC.currentTime() will always return 0.
        // 
        // *** We need RTC to be enabled because it keeps BAKMEM alive.
        // *** If RTC is disabled, we enter LPM4.5 when we sleep
        // *** (instead of LPM3.5), and BAKMEM is lost.
        if (_StartTime.valid) {
            FRAMWriteEn writeEn; // Enable FRAM writing
            
            // Mark the time as invalid before consuming it, so that if we lose power,
            // the time won't be reused again
            _StartTime.valid = false;
            // Init real-time clock
            _RTC.init(_StartTime.time);
        
        } else {
            _RTC.init(0);
        }
    }
    
    // Init WDT
    _WDT::Init();
    
    _Scheduler::Run();
}

extern "C" [[noreturn]]
void abort() {
    _Pin::DEBUG_OUT::Init();
    for (bool x=0;; x=!x) {
        _Pin::DEBUG_OUT::Write(x);
    }
}
