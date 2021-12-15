#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "SDCard.h"
#include "ICE.h"
#include "ImgSensor.h"
#include "ImgAutoExposure.h"
#include "Startup.h"
#include "GPIO.h"
#include "Clock.h"
#include "RTC.h"
#include "SPI.h"
#include "FRAMWriteEn.h"
#include "Util.h"
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"
using namespace Toastbox;
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz = 16000000;
static constexpr uint32_t _XT1FreqHz = 32768;
static constexpr uint16_t _LPMBits = LPM3_bits;

#define _delayUs(us) __delay_cycles((((uint64_t)us)*_MCLKFreqHz) / 1000000)
#define _delayMs(ms) __delay_cycles((((uint64_t)ms)*_MCLKFreqHz) / 1000)

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
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN, _Pin::ICE_MSP_SPI_DATA_DIR>;

class _MainTask;
class _SDTask;
class _ImgTask;
using _Scheduler = Toastbox::Scheduler<
    _MainTask,
    _SDTask,
    _ImgTask
>;

__attribute__((section(".ram_backup.main")))
static SD::Card _SD;

// _StartTime: the time set by STM32 (seconds since reference date)
// Stored in 'Information Memory' (FRAM) because it needs to persist across a cold start.
__attribute__((section(".fram_info.main")))
static volatile struct {
    uint32_t time   = 0;
    uint16_t valid  = false; // uint16_t (instead of bool) for alignment
} _StartTime;

// _RTC: real time clock
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
__attribute__((section(".ram_backup.main")))
static RTC<_XT1FreqHz> _RTC;

// _ImgAutoExp: auto exposure algorithm object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
__attribute__((section(".ram_backup.main")))
static Img::AutoExposure _ImgAutoExp;

// _ImgIndexes: stats to track captured images
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely.
__attribute__((section(".fram_info.main")))
static volatile struct {
    uint32_t counter = 0;
    uint16_t write = 0;
    uint16_t read = 0;
    bool full = false;
} _ImgIndexes;








class _SDTask {
public:
    using Options = _Scheduler::Options<
        _Scheduler::Option::Start // Task should start running
    >;
    
    static void Run() {
        for (;;) {
            _Scheduler::Wait([&] {
                return (bool)Cmd;
            });
            
            switch (*Cmd) {
            case Command::Enable:
                // Power on + initialize SD card
                _SD.init();
                break;
            
            case Command::Disable:
                #warning we should tell ICE40 to disable SD clock before powering off SD card
                // Power off SD card
                SD::Card::SetPowerEnabled(false);
                break;
            }
            
            Cmd = std::nullopt;
        }
    }
    
    __attribute__((section(".stack._SDTask")))
    static inline uint8_t Stack[128];
    
    enum class Command {
        Enable,
        Disable,
    };
    
    static inline std::optional<Command> Cmd;
};

class _ImgTask {
public:
    using Options = _Scheduler::Options<
        _Scheduler::Option::Start // Task should start running
    >;
    
    static void Run() {
        for (;;) {
            _Scheduler::Wait([&] {
                return (bool)Cmd;
            });
            
            switch (*Cmd) {
            case Command::Enable:
                // Initialize image sensor
                Img::Sensor::Init();
                
                // Set the initial exposure _before_ we enable streaming, so that the very first frame
                // has the correct exposure, so we don't have to skip any frames on the first capture.
                Img::Sensor::SetCoarseIntTime(_ImgAutoExp.integrationTime());
                
                // Enable image streaming
                Img::Sensor::SetStreamEnabled(true);
                break;
            
            case Command::Disable:
                Img::Sensor::SetPowerEnabled(false);
                break;
            }
            
            Cmd = std::nullopt;
        }
    }
    
    __attribute__((section(".stack._ImgTask")))
    static inline uint8_t Stack[128];
    
    enum class Command {
        Enable,
        Disable,
    };
    
    static inline std::optional<Command> Cmd;
};






static void _SetSDImgEnabled(bool en) {
    static bool powerEn = false;
    if (powerEn == en) return; // Short circuit if state didn't change
    
    powerEn = en;
    if (powerEn) {
        // Initialize the SD card and image sensor in parallel
        _SDTask::Cmd = _SDTask::Command::Enable;
        _ImgTask::Cmd = _ImgTask::Command::Enable;
    
    } else {
        // Initialize the SD card and image sensor in parallel
        _SDTask::Cmd = _SDTask::Command::Disable;
        _ImgTask::Cmd = _ImgTask::Command::Disable;
    }
    
    // Wait until both the SD card and image sensor are initialized
    _Scheduler::Wait([&] {
        return !_SDTask::Cmd && !_ImgTask::Cmd;
    });
}

// MARK: - Motion

static void _MotionHandle() {
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
        auto resp = ICE::ImgCapture(header, expBlock, skipCount);
        Assert((bool)resp);
        
        const uint8_t expScore = _ImgAutoExp.update((*resp).highlightCount(), (*resp).shadowCount());
        if (!bestExpScore || (expScore > bestExpScore)) {
            bestExpBlock = expBlock;
            bestExpScore = expScore;
        }
        
        // We're done if we don't have any exposure changes
        if (!_ImgAutoExp.changed()) break;
        
        // Update the exposure
        Img::Sensor::SetCoarseIntTime(_ImgAutoExp.integrationTime());
    }
    
    // Write the best-exposed image to the SD card
    _SD.writeImage(bestExpBlock, _ImgIndexes.write);
    
    // Update _ImgIndexes
    {
        FRAMWriteEn writeEn; // Enable FRAM writing
        _ImgIndexes.write++;
        _ImgIndexes.counter++;
    }
}

// MARK: - Interrupts

__attribute__((interrupt(RTC_VECTOR)))
static void _ISR_RTC() {
    _RTC.isr();
}

static volatile bool _Motion = false;

__attribute__((interrupt(PORT2_VECTOR)))
void _ISR_Port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV__P2IFG5)) {
    case P2IV__P2IFG5:
        _Motion = true;
        // Wake ourself
        __bic_SR_register_on_exit(GIE | LPM3_bits);
        break;
    
    default:
        break;
    }
}

__attribute__((interrupt(WDT_VECTOR)))
static void _ISR_WDT() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(GIE | LPM3_bits);
    }
}

// MARK: - ICE40

void ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & ICE::MsgType::Resp));
    
    static bool iceInit = false;
    // Init ICE40 if we haven't done so yet
    if (!iceInit) {
        iceInit = true;
        
        // Init SPI/ICE40
        if (Startup::ColdStart()) {
            constexpr bool iceReset = true; // Cold start -> reset ICE40 SPI state machine
            _SPI::Init(iceReset);
            ICE::Init(); // Cold start -> init ICE40 to verify that comms are working
        
        } else {
            constexpr bool iceReset = false; // Warm start -> no need to reset ICE40 SPI state machine
            _SPI::Init(iceReset);
        }
    }
    
    _SPI::WriteRead(msg, resp);
}

// MARK: - SD Card

const uint8_t SD::Card::ClkDelaySlow = 1; // Odd values invert the clock
const uint8_t SD::Card::ClkDelayFast = 0;

void SD::Card::SetPowerEnabled(bool en) {
    _Pin::VDD_SD_EN::Write(en);
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _delayMs(2);
}

// MARK: - Image Sensor

void Img::Sensor::SetPowerEnabled(bool en) {
    if (en) {
        _Pin::VDD_2V8_IMG_EN::Write(1);
        _delayUs(100); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V9)
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
    const uint16_t LPMBits = (_Motion ? LPM1_bits : LPM3_bits);
    
    // If we're entering LPM3, disable regulator so we enter LPM3.5 (instead of just LPM3)
    if (LPMBits == LPM3_bits) {
        PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
        PMMCTL0_L |= PMMREGOFF;
    }
    
    // Atomically enable interrupts and go to sleep
    const bool prevEn = Toastbox::IntState::InterruptsEnabled();
    __bis_SR_register(GIE | _LPMBits);
    // If interrupts were disabled previously, disable them again
    if (!prevEn) Toastbox::IntState::SetInterruptsEnabled(false);
}

// MARK: - Tasks

//static void debugSignal() {
//    _Pin::DEBUG_OUT::Init();
//    for (int i=0; i<10; i++) {
//        _Pin::DEBUG_OUT::Write(0);
//        _delayMs(10);
//        _Pin::DEBUG_OUT::Write(1);
//        _delayMs(10);
//    }
//}

class _MainTask {
public:
    using Options = _Scheduler::Options<
        _Scheduler::Option::Start // Task should start running
    >;
    
    static void Run() {
        for (;;) {
            // Wait for motion
            _Scheduler::Wait([&] { return _Motion; });
            
            ICE::Transfer(ICE::LEDSetMsg(0xFF));
            
            // Turn everything on
            _SetSDImgEnabled(true);
            
            // Handle motion
            _MotionHandle();
            
            ICE::Transfer(ICE::LEDSetMsg(0x00));
            _delayMs(100);
            
            _Motion = false;
        }
    }
    
    __attribute__((section(".stack.MotionTask")))
    static inline uint8_t Stack[128];
};




#define _StackMainSize 128

__attribute__((section(".stack.main")))
uint8_t _StackMain[_StackMainSize];

asm(".global __stack");
asm("__stack = _StackMain+" Stringify(_StackMainSize));


int main() {
    // Config watchdog timer:
    //   WDTPW:             password
    //   WDTSSEL__SMCLK:    watchdog source = SMCLK
    //   WDTTMSEL:          interval timer mode
    //   WDTCNTCL:          clear counter
    //   WDTIS__8192:       interval = SMCLK / 8192 Hz = 16MHz / 8192 = 1953.125 Hz => period=512 us
    WDTCTL = WDTPW | WDTSSEL__SMCLK | WDTTMSEL | WDTCNTCL | WDTIS__8192;
    SFRIE1 |= WDTIE; // Enable WDT interrupt
    
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
    
    if (Startup::ColdStart()) {
        // If we do have a valid startTime, consume _startTime and hand it off to _RTC.
        // Otherwise, initialize _RTC with 0. This will enable RTC, but it won't
        // enable the interrupt, so _RTC.currentTime() will always return 0.
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
    
    _Scheduler::Run();
}

extern "C" [[noreturn]]
void abort() {
    _Pin::DEBUG_OUT::Init();
    for (bool x=0;; x=!x) {
        _Pin::DEBUG_OUT::Write(x);
    }
}
