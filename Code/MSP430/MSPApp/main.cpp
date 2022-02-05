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
#include "BusyAssertion.h"
#include "Toastbox/IntState.h"
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _XT1FreqHz        = 32768;
static constexpr uint32_t _SysTickPeriodUs  = 512;

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line);

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
    using MOTION_SIGNAL                     = PortA::Pin<0xD, Option::Resistor0>; // Motion sensor can only pull up, so it requires a pulldown resistor
//    using MOTION_SIGNAL                     = PortA::Pin<0xD, Option::Resistor0, Option::Interrupt01>; // Motion sensor can only pull up, so it requires a pulldown resistor
    
    using DEBUG_OUT                         = PortA::Pin<0xE, Option::Output0>;
};

using _Clock = ClockType<_XT1FreqHz, _MCLKFreqHz, _Pin::XOUT, _Pin::XIN>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
using _SPI = SPIType<_MCLKFreqHz, _Pin::ICE_MSP_SPI_CLK, _Pin::ICE_MSP_SPI_DATA_OUT, _Pin::ICE_MSP_SPI_DATA_IN, _Pin::ICE_MSP_SPI_DATA_DIR>;

class _MotionTask;

static void _Sleep();

static void _SchedulerError(uint16_t line);
static void _ICEError(uint16_t line);
static void _SDError(uint16_t line);
//static void _ImgError(uint16_t line);

static bool _SDSetPowerEnabled(bool en);

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
    _MotionTask                                 // T_Tasks: list of tasks
>;

using _ICE = ICE<
    _Scheduler,
    _ICEError
>;

// _SDCard: SD card object
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
using _SDCard = SD::Card<
    _Scheduler,         // T_Scheduler
    _ICE,               // T_ICE
    _SDSetPowerEnabled, // T_SetPowerEnabled
    _SDError,           // T_Error
    1,                  // T_ClkDelaySlow (odd values invert the clock)
    0                   // T_ClkDelayFast (odd values invert the clock)
>;

// _RTC: real time clock
// Stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep, but reset upon a cold start.
// 
// _RTC needs to live in the _noinit variant, so that RTC memory
// is never automatically initialized, because we don't want it
// to be reset when we abort.
[[gnu::section(".ram_backup_noinit.main")]]
static RTC::Type<_XT1FreqHz> _RTC;

// _State: stores MSPApp persistent state, intended to be read/written by outside world
// Stored in 'Information Memory' (FRAM) because it needs to persist indefinitely
[[gnu::section(".fram_info.main")]]
static MSP::State _State;

// _Motion: announces that motion occurred
// volatile because _Motion is modified from the interrupt context
static volatile bool _Motion = false;

// _BusyCount: counts the number of entities preventing LPM3.5 sleep
static uint8_t _BusyCount = 0;
using _BusyAssertion = BusyAssertionType<_BusyCount>;

// MARK: - Motion

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
        __bic_SR_register_on_exit(LPM3_bits);
        break;
    
    default:
        break;
    }
}

[[gnu::interrupt(WDT_VECTOR)]]
static void _ISR_SysTick() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(LPM3_bits);
    }
}

// MARK: - ICE40

template<>
void _ICE::Transfer(const Msg& msg, Resp* resp) {
    AssertArg((bool)resp == (bool)(msg.type & _ICE::MsgType::Resp));
    
    // Init SPI peripheral
    static bool spiInit = false;
    if (!spiInit) {
        spiInit = true;
        _SPI::Init();
    }
    
    // iceInit: Stored in BAKMEM (RAM that's retained in LPM3.5) so that
    // it's maintained during sleep, but reset upon a cold start.
    [[gnu::section(".ram_backup.main")]]
    static bool iceInit = false;
    
    // Init ICE comms
    if (!iceInit) {
        iceInit = true;
        // Reset ICE comms (by asserting SPI CLK for some length of time)
        _SPI::ICEReset();
        // Init ICE comms
        _ICE::Init();
    }
    
//    // Init ICE40 if we haven't done so yet
//    static bool iceInit = false;
//    if (!iceInit) {
//        // Init SPI/ICE40
//        if (Startup::ColdStart()) {
//            constexpr bool iceReset = true; // Cold start -> reset ICE40 SPI state machine
//            _SPI::Init(iceReset);
//            _ICE::Init(); // Cold start -> init ICE40 to verify that comms are working
//        
//        } else {
//            constexpr bool iceReset = false; // Warm start -> no need to reset ICE40 SPI state machine
//            _SPI::Init(iceReset);
//        }
//    }
    
    _SPI::WriteRead(msg, resp);
}

// MARK: - Power

static bool _SDSetPowerEnabled(bool en) {
    #warning TODO: short-circuit if the pin state isn't changing, to save time
    
    _Pin::VDD_SD_EN::Write(en);
    // The TPS22919 takes 1ms for VDD to reach 2.8V (empirically measured)
    _Scheduler::Sleep(_Scheduler::Ms(2));
    return true;
}

// MARK: - IntState

inline bool Toastbox::IntState::InterruptsEnabled() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

static void _Sleep() {
    // Put ourself to sleep until an interrupt occurs. This function may or may not return:
    // 
    // - This function returns if an interrupt was already pending and the ISR
    //   wakes us (via `__bic_SR_register_on_exit`). In this case we never enter LPM3.5.
    // 
    // - This function doesn't return if an interrupt wasn't pending and
    //   therefore we enter LPM3.5. The next time we wake will be due to a
    //   reset and execution will start from main().
    
    // If we're currently busy (_BusyCount > 0), enter LPM1 sleep because some tasks are running.
    // If we're not busy (!_BusyCount), enter the deep LPM3.5 sleep, where RAM content is lost.
//    const uint16_t LPMBits = (_BusyCount ? LPM1_bits : LPM3_bits);
    const uint16_t LPMBits = LPM1_bits;
    
    // If we're entering LPM3, disable regulator so we enter LPM3.5 (instead of just LPM3)
    if (LPMBits == LPM3_bits) {
        PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
        PMMCTL0_L |= PMMREGOFF_1_L;
    }
    
    // Atomically enable interrupts and go to sleep
    const bool prevEn = Toastbox::IntState::InterruptsEnabled();
    __bis_SR_register(GIE | LPMBits);
    // If interrupts were disabled previously, disable them again
    if (!prevEn) Toastbox::IntState::SetInterruptsEnabled(false);
}

// MARK: - Tasks

struct _MotionTask {
    static void Run() {
        for (;;) {
            volatile bool a = false;
            while (!a);
            
//            _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
            
            _SDCard::Disable();
            
            _SDCard::Enable();
//            for (;;) {
//                _BusyAssertion busy;
//                
//                volatile bool a = false;
//                while (!a);
//                
//                // Capture an image
//                _ICE::Transfer(_ICE::LEDSetMsg(0xFF));
//                
//                _SD::EnableAsync();
//                _SD::Wait();
//                _SD::WriteImage(0, 0);
//                
//                _ICE::Transfer(_ICE::LEDSetMsg(0x00));
//            }
        }
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._MotionTask")]]
    static inline uint8_t Stack[256];
};

// MARK: - Abort

namespace AbortDomain {
    static constexpr uint16_t Invalid       = 0;
    static constexpr uint16_t General       = 1;
    static constexpr uint16_t Scheduler     = 2;
    static constexpr uint16_t ICE           = 3;
    static constexpr uint16_t SD            = 4;
    static constexpr uint16_t Img           = 5;
}

[[noreturn]]
static void _SchedulerError(uint16_t line) {
    _Abort(AbortDomain::Scheduler, line);
}

[[noreturn]]
static void _ICEError(uint16_t line) {
    _Abort(AbortDomain::ICE, line);
}

[[noreturn]]
static void _SDError(uint16_t line) {
    _Abort(AbortDomain::SD, line);
}

static void _AbortRecord(const MSP::Time& time, uint16_t domain, uint16_t line) {
    FRAMWriteEn writeEn; // Enable FRAM writing
    
    auto& abort = _State.abort;
    if (abort.eventsCount >= std::size(abort.events)) return;
    
    abort.events[abort.eventsCount] = MSP::AbortEvent{
        .time = time,
        .domain = domain,
        .line = line,
    };
    
    abort.eventsCount++;
}

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line) {
    const MSP::Time time = _RTC.time();
    // Record the abort
    _AbortRecord(time, domain, line);
    // Trigger a BOR
    PMMCTL0 = PMMPW | PMMSWBOR;
    for (;;);
}

extern "C" [[noreturn]]
void abort() {
    _Abort(AbortDomain::General, 0);
}

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
    
//    volatile bool a = false;
//    while (!a);
    
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
    
//    _Pin::DEBUG_OUT::Init();
//    for (uint32_t i=0; i<1000000; i++) {
//        _Pin::DEBUG_OUT::Write(1);
//        _Pin::DEBUG_OUT::Write(0);
//    }
    
    #warning if this is a cold start:
    #warning   wait a few milliseconds to allow our outputs to settle so that our peripherals
    #warning   (SD card, image sensor) fully turn off, because we may have restarted because
    #warning   of an error
    
    #warning we're currently sleeping before we abort -- move that sleep here instead.
    
    #warning how do we handle turning off SD clock after an error occurs?
    #warning   ? dont worry about that because in the final design,
    #warning   well be powering off ICE40 anyway?
    
    // Start RTC if it's not currently enabled.
    // We need RTC to be unconditionally enabled for 2 reasons:
    //   - We want to track relative time (ie system uptime) even if we don't know the wall time.
    //   - RTC must be enabled to keep BAKMEM alive when sleeping. If RTC is disabled, we enter
    //     LPM4.5 when we sleep (instead of LPM3.5), and BAKMEM is lost.
    if (_State.startTime.valid) {
        // If _StartTime is valid, consume it and hand it off to _RTC.
        FRAMWriteEn writeEn; // Enable FRAM writing
        // Mark the time as invalid before consuming it, so that if we lose power,
        // the time won't be reused again
        _State.startTime.valid = false;
        // Init real-time clock
        _RTC.init(_State.startTime.time);
    
    // Otherwise, we don't have a valid _State.startTime, so if _RTC isn't currently
    // enabled, init _RTC with 0.
    } else if (!_RTC.enabled()) {
        _RTC.init(0);
    }
    
    // Init SysTick
    _SysTick::Init();
    
//    // If this is a cold start, delay 3s before beginning.
//    // This delay is meant for the case where we restarted due to an abort, and
//    // serves 2 purposes:
//    //   1. it rate-limits aborts, in case there's a persistent issue
//    //   2. it allows GPIO outputs to settle, so that peripherals fully turn off
//    if (Startup::ColdStart()) {
//        _BusyAssertion busy; // Prevent LPM3.5 sleep during the delay
//        _Scheduler::Delay(_Scheduler::Ms(3000));
//    }
    
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
//const _DebugStack& _Debug_MotionTaskStack         = *(_DebugStack*)_MotionTask::Stack;
//const _DebugStack& _Debug_SDTaskStack             = *(_DebugStack*)_SDTask::Stack;
//const _DebugStack& _Debug_ImgTaskStack            = *(_DebugStack*)_ImgTask::Stack;
