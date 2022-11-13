#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include <atomic>
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
#include "MSP.h"
#include "GetBits.h"
#include "Toastbox/IntState.h"
#include "ImgSD.h"
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _XT1FreqHz        = 32768;
static constexpr uint32_t _SysTickPeriodUs  = 512;

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line);

struct _Pin {
    // Default GPIOs
    using UNUSED0                           = PortA::Pin<0x0>;
    using DEBUG_OUT                         = PortA::Pin<0x1, Option::Output0>;
    using VDD_B_EN                          = PortA::Pin<0x2, Option::Output0>;
    using MOTION_SIGNAL                     = PortA::Pin<0x3, Option::Input, Option::Resistor0>; // Motion sensor can only pull up, so it requires a pulldown resistor
//    using MOTION_SIGNAL                     = PortA::Pin<0x3, Option::Interrupt01, Option::Resistor0>; // Motion sensor can only pull up, so it requires a pulldown resistor
    using UNUSED4                           = PortA::Pin<0x4>;
    using UNUSED5                           = PortA::Pin<0x5>;
    using VDD_B_2V8_IMG_SD_EN               = PortA::Pin<0x6, Option::Input, Option::Resistor0>; // Weakly controlled to allow STM to override
    using UNUSED7                           = PortA::Pin<0x7>;
    using XOUT                              = PortA::Pin<0x8>;
    using XIN                               = PortA::Pin<0x9>;
    using HOST_MODE_                        = PortA::Pin<0xA, Option::Input, Option::Resistor0>;
    using VDD_B_1V8_IMG_SD_EN               = PortA::Pin<0xB, Option::Input, Option::Resistor0>; // Weakly controlled to allow STM to override
    using ICE_MSP_SPI_CLK                   = PortA::Pin<0xC>;
    using ICE_MSP_SPI_DATA_OUT              = PortA::Pin<0xD>;
    using ICE_MSP_SPI_DATA_IN               = PortA::Pin<0xE>;
};

using _Clock = ClockType<_MCLKFreqHz>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN>;

class _MainTask;
class _SDTask;

static void _Sleep();

static void _SchedulerError(uint16_t line);
static void _ICEError(uint16_t line);
static void _SDError(uint16_t line);

extern uint8_t _StackMain[];

#warning disable stack guard for production
static constexpr size_t _StackGuardCount = 16;
using _Scheduler = Toastbox::Scheduler<
    _SysTickPeriodUs,                           // T_UsPerTick: microseconds per tick
    Toastbox::IntState::SetInterruptsEnabled,   // T_SetInterruptsEnabled: function to change interrupt state
    _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                //          invoked when no tasks have work to do
    _SchedulerError,                            // T_Error: function to handle unrecoverable error
    _StackMain,                                 // T_MainStack: main stack pointer (only used to monitor
                                                //              main stack for overflow; unused if T_StackGuardCount==0)
    _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
    _MainTask,                                  // T_Tasks: list of tasks
    _SDTask
>;

using _ICE = ICE<
    _Scheduler,
    _ICEError
>;

// _SDCard: SD card object
using _SDCard = SD::Card<
    _Scheduler,         // T_Scheduler
    _ICE,               // T_ICE
    _SDError,           // T_Error
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    6                   // T_ClkDelayFast (odd values invert the clock)
>;

using _RTCType = RTC::Type<_XT1FreqHz, _Pin::XOUT, _Pin::XIN>;

// _RTC: real time clock
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
// 
// _RTC needs to live in the _noinit variant, so that RTC memory
// is never automatically initialized, because we don't want it
// to be reset when we abort.
[[gnu::section(".ram_backup_noinit.main")]]
static _RTCType _RTC;

// _State: stores MSPApp persistent state, intended to be read/written by outside world
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely
[[gnu::section(".fram_info.main")]]
static MSP::State _State;

// MARK: - Power

static void _VDDBSetEnabled(bool en) {
    _Pin::VDD_B_EN::Write(en);
}

static void _VDDIMGSDSetEnabled(bool en) {
    // Short-circuit if the pin state hasn't changed, to save us the Sleep()
    if (_Pin::VDD_B_2V8_IMG_SD_EN::Read() == en) return;
    
    if (en) {
        _Pin::VDD_B_2V8_IMG_SD_EN::Write(1);
        _Scheduler::Sleep(_Scheduler::Us(100)); // 100us delay needed between power on of VAA (2V8) and VDD_IO (1V8)
        _Pin::VDD_B_1V8_IMG_SD_EN::Write(1);
        
        // Rails take ~1ms to turn on, so wait 2ms to be sure
        _Scheduler::Sleep(_Scheduler::Ms(2));
    
    } else {
        // No delay between 2V8/1V8 needed for power down (per AR0330CS datasheet)
        _Pin::VDD_B_2V8_IMG_SD_EN::Write(0);
        _Pin::VDD_B_1V8_IMG_SD_EN::Write(0);
        
        // Rails take ~1.5ms to turn off, so wait 2ms to be sure
        _Scheduler::Sleep(_Scheduler::Ms(2));
    }
}

// MARK: - ICE40

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    _SPI::WriteRead(msg, resp);
}

// MARK: - Tasks

static void debugSignal() {
    _Pin::DEBUG_OUT::Init();
    for (;;) {
//    for (int i=0; i<10; i++) {
        _Pin::DEBUG_OUT::Write(0);
        for (volatile int i=0; i<10000; i++);
        _Pin::DEBUG_OUT::Write(1);
        for (volatile int i=0; i<10000; i++);
    }
}

struct _SDTask {
    static void Reset() {
        Wait();
        _Scheduler::Start<_SDTask>([] { _Reset(); });
    }
    
    static void Init() {
        Wait();
        _Scheduler::Start<_SDTask>([] { _Init(); });
    }
    
    static void Wait() {
        _Scheduler::Wait<_SDTask>();
    }
    
    static void _Reset() {
        _SDCard::Reset();
    }
    
    static void _Init() {
        _SDCard::Init();
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{};
    
    // Task stack
    [[gnu::section(".stack._SDTask")]]
    static inline uint8_t Stack[256];
};

// CCIFG0 interrupt
[[gnu::interrupt(TIMER0_A0_VECTOR)]]
static void _ISR_TIMER0_A0() {
    __bic_SR_register_on_exit(LPM3_bits);
}

struct _MainTask {
    static void Run() {
        const MSP::ImgRingBuf& imgRingBuf = _State.sd.imgRingBufs[0];
        
        // Init SPI peripheral
        _SPI::Init();
        
        // Turn on VDD_B power (turns on ICE40)
        _VDDBSetEnabled(true);
        
        // Wait for ICE40 to start
        // We specify (within the bitstream itself, via icepack) that ICE40 should load
        // the bitstream at high-frequency (40 MHz).
        // According to the datasheet, this takes 70ms.
        _Scheduler::Sleep(_Scheduler::Ms(75));
        
        // Reset ICE comms (by asserting SPI CLK for some length of time)
        _SPI::ICEReset();
        
        // Init ICE comms
        _ICE::Init();
        
        for (;;) {
            // Reset SD nets before we turn on SD power
            _SDTask::Reset();
            _SDTask::Wait();
            
            // Turn on IMG/SD power
            _VDDIMGSDSetEnabled(true);
            
            // Init image sensor / SD card
            _SDTask::Init();
            
            // Capture an image
            {
                _ICE::Transfer(_ICE::LEDSetMsg(0xF));
                _Scheduler::Sleep(_Scheduler::Ms(100));
                _ICE::Transfer(_ICE::LEDSetMsg(0x0));
            }
            
            // Turn off power
            _VDDIMGSDSetEnabled(false);
            
            _Scheduler::Sleep(_Scheduler::Ms(1000));
        }
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._MainTask")]]
    static inline uint8_t Stack[256];
};

// MARK: - IntState

inline bool Toastbox::IntState::InterruptsEnabled() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

static void _Sleep() {
    // Atomically enable interrupts and go to sleep
    const bool prevEn = Toastbox::IntState::InterruptsEnabled();
    __bis_SR_register(GIE | LPM1_bits);
    // If interrupts were disabled previously, disable them again
    if (!prevEn) Toastbox::IntState::SetInterruptsEnabled(false);
}

// MARK: - Interrupts

[[gnu::interrupt(RTC_VECTOR)]]
static void _ISR_RTC() {
    _RTC.isr();
}

[[gnu::interrupt(WDT_VECTOR)]]
static void _ISR_SysTick() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

// MARK: - Abort

namespace AbortDomain {
    static constexpr uint16_t Invalid       = 0;
    static constexpr uint16_t General       = 1;
    static constexpr uint16_t Scheduler     = 2;
    static constexpr uint16_t ICE           = 3;
    static constexpr uint16_t SD            = 4;
    static constexpr uint16_t Img           = 5;
}

static void _AbortRecord(const MSP::Time& timestamp, uint16_t domain, uint16_t line) {
    FRAMWriteEn writeEn; // Enable FRAM writing
    
    auto& abort = _State.abort;
    if (abort.eventsCount >= std::size(abort.events)) return;
    
    abort.events[abort.eventsCount] = MSP::AbortEvent{
        .timestamp = timestamp,
        .domain = domain,
        .line = line,
    };
    
    abort.eventsCount++;
}

[[noreturn]]
static void _SchedulerError(uint16_t line) {
    _Abort(AbortDomain::Scheduler, line);
}

[[noreturn]]
static void _ICEError(uint16_t line) {
    _Abort(AbortDomain::ICE, line);
}

static void _SDError(uint16_t line) {
    const MSP::Time timestamp = _RTC.time();
    _AbortRecord(timestamp, AbortDomain::SD, line);
}

[[noreturn]]
static void _BOR() {
    PMMCTL0 = PMMPW | PMMSWBOR;
    for (;;);
}

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line) {
    const MSP::Time timestamp = _RTC.time();
    // Record the abort
    _AbortRecord(timestamp, domain, line);
    _BOR();
}

extern "C" [[noreturn]]
void abort() {
    _Abort(AbortDomain::General, 0);
    for (;;);
}

// MARK: - Main

#warning verify that _StackMainSize is large enough
#define _StackMainSize 128

[[gnu::section(".stack.main")]]
uint8_t _StackMain[_StackMainSize];

asm(".global __stack");
asm(".equ __stack, _StackMain+" Stringify(_StackMainSize));

static void _HostMode() {
    // Let power rails fully discharge before turning them on
    _Scheduler::Delay(_Scheduler::Ms(10));
    
    while (!_Pin::HOST_MODE_::Read()) {
        _Scheduler::Delay(_Scheduler::Ms(100));
    }
}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIO::Init<
        // General IO
        _Pin::DEBUG_OUT,
        _Pin::MOTION_SIGNAL,
        _Pin::HOST_MODE_,
        
        // Power control
        _Pin::VDD_B_EN,
        _Pin::VDD_B_1V8_IMG_SD_EN,
        _Pin::VDD_B_2V8_IMG_SD_EN,
        
        // Clock (config chosen by _RTCType)
        _RTCType::Pin::XOUT,
        _RTCType::Pin::XIN,
        
        // SPI (config chosen by _SPI)
        _SPI::Pin::Clk,
        _SPI::Pin::DataOut,
        _SPI::Pin::DataIn
    >();
    
    // We're using the 'remapped' pin assignments for the eUSCI_B0 pins, which requires setting SYSCFG2.USCIBRMP.
    // See "Table 9-11. eUSCI Pin Configurations" in the datasheet.
    SYSCFG2 |= USCIBRMP;
    
    // Init clock
    _Clock::Init();
    
    // Init RTC
    // We need RTC to be unconditionally enabled for 2 reasons:
    //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
    //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
    //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
    MSP::Time startTime = 0;
    if (_State.startTime.valid) {
        startTime = _State.startTime.time;
        
        // If `time` is valid, consume it before handing it off to _RTC.
        FRAMWriteEn writeEn; // Enable FRAM writing
        // Reset `valid` before consuming the start time, so that if we lose power,
        // the time won't be reused again
        _State.startTime.valid = false;
        std::atomic_signal_fence(std::memory_order_seq_cst);
    }
    _RTC.init(startTime);
    
    // Init SysTick
    _SysTick::Init();
    
//    {
//        _Pin::VDD_B_EN::Write(1);
//        _Scheduler::Delay(_Scheduler::Ms(1000));
//        
////        debugSignal();
//        
//        for (;;) {
//            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
//            _Scheduler::Delay(_Scheduler::Ms(250));
//            
//            _ICE::Transfer(_ICE::LEDSetMsg(0x00));
//            _Scheduler::Delay(_Scheduler::Ms(250));
//        }
//    }
    
    // Handle cold starts
    if (Startup::ColdStart()) {
        // Temporarily enable a pullup on HOST_MODE_ so that we can determine whether STM is driving it low.
        // We don't want the pullup to be permanent to prevent leakage current (~80nA) through STM32's GPIO
        // that controls HOST_MODE_.
        _Pin::HOST_MODE_::Write(1);
        
        // Wait for the pullup to pull the rail up
        _Scheduler::Delay(_Scheduler::Ms(1));
        
        // Enter host mode if HOST_MODE_ is asserted
        if (!_Pin::HOST_MODE_::Read()) {
            _HostMode();
        }
        
        // Return to default HOST_MODE_ config
        // Not using GPIO::Init() here because it costs a lot more instructions.
        _Pin::HOST_MODE_::Write(0);
        
        // Since this is a cold start, delay 3s before beginning.
        // This delay is meant for the case where we restarted due to an abort, and
        // serves 2 purposes:
        //   1. it rate-limits aborts, in case there's a persistent issue
        //   2. it allows GPIO outputs to settle, so that peripherals fully turn off
        _Scheduler::Delay(_Scheduler::Ms(1000));
    }
    
    _Scheduler::Run();
}




//#warning TODO: remove these debug symbols
//#warning TODO: when we remove these, re-enable: Project > Optimization > Place [data/functions] in own section
//constexpr auto& _Debug_Tasks              = _Scheduler::_Tasks;
//constexpr auto& _Debug_DidWork            = _Scheduler::_DidWork;
//constexpr auto& _Debug_CurrentTask        = _Scheduler::_CurrentTask;
//constexpr auto& _Debug_CurrentTime        = _Scheduler::_ISR.CurrentTime;
//constexpr auto& _Debug_Wake               = _Scheduler::_ISR.Wake;
//constexpr auto& _Debug_WakeTime           = _Scheduler::_ISR.WakeTime;
//
//struct _DebugStack {
//    uint16_t stack[_StackGuardCount];
//};
//
//const _DebugStack& _Debug_MainStack               = *(_DebugStack*)_StackMain;
//const _DebugStack& _Debug_MainTaskStack         = *(_DebugStack*)_MainTask::Stack;
//const _DebugStack& _Debug_SDTaskStack             = *(_DebugStack*)_SDTask::Stack;
//const _DebugStack& _Debug_ImgTaskStack            = *(_DebugStack*)_ImgTask::Stack;
