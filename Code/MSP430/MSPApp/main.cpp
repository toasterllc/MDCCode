#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "Startup.h"
#include "GPIO.h"
#include "Clock.h"
#include "SPI.h"
#include "FRAMWriteEn.h"
#include "Util.h"
#include "Toastbox/IntState.h"
#include "Toastbox/Task.h"
using namespace Toastbox;
using namespace GPIO;

static constexpr uint64_t _MCLKFreqHz = 16000000;
static constexpr uint32_t _XT1FreqHz = 32768;

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

class _MotionTask;
class _BusyTimeoutTask;
using _Scheduler = Toastbox::Scheduler<
    _MotionTask,
    _BusyTimeoutTask
>;

// MARK: - Sleep

static constexpr uint32_t _UsPerTick = 512;

static _Scheduler::Ticks _TicksForUs(uint32_t us) {
    // We're intentionally not ceiling the result because _Scheduler::Sleep
    // implicitly ceils by adding one tick (to prevent truncated sleeps)
    return us / _UsPerTick;
}

void SleepMs(uint16_t ms) {
    _Scheduler::Sleep(_TicksForUs(1000*(uint32_t)ms));
}

void SleepUs(uint16_t us) {
    _Scheduler::Sleep(_TicksForUs(us));
}

// MARK: - Motion

static volatile bool _Motion = false;
static volatile bool _Busy = false;

// MARK: - Interrupts

[[gnu::interrupt(PORT2_VECTOR)]]
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

[[gnu::interrupt(WDT_VECTOR)]]
static void _ISR_WDT() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(GIE | LPM3_bits);
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
//    const uint16_t LPMBits = (_Busy ? LPM1_bits : LPM3_bits);
    const uint16_t LPMBits = LPM1_bits;
    
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

class _MotionTask {
public:
    using Options = _Scheduler::Options<
        _Scheduler::Option::Start // Task should start running
    >;
    
    static void Run() {
        for (;;) {
            // Wait for motion
            _Scheduler::Wait([&] { return _Motion; });
            _Motion = false;
            _Busy = true;
            
            // Stop the timeout task while we capture a new image
            _Scheduler::Stop<_BusyTimeoutTask>();
            
            SleepMs(100);
            SleepMs(100);
            
            // Restart the timeout task, so that we turn off automatically if
            // we're idle for a bit
            _Scheduler::Start<_BusyTimeoutTask>();
        }
    }
    
    #warning TODO: reduce stack sizes once we figure out the problem
    __attribute__((section(".stack._MotionTask")))
    static inline uint8_t Stack[256];
};

class _BusyTimeoutTask {
public:
    using Options = _Scheduler::Options<>;
    
    static void Run() {
        for (;;) {
            // Stay on for 1 second waiting for motion
            SleepMs(1000);
            
            // Update our state
            _Busy = false;
        }
    }
    
    __attribute__((section(".stack._BusyTimeoutTask")))
    static inline uint8_t Stack[256];
};

// MARK: - Main

#warning verify that _StackMainSize is large enough
#define _StackMainSize 256

__attribute__((section(".stack.main")))
uint8_t _StackMain[_StackMainSize];

asm(".global __stack");
asm("__stack = _StackMain+" Stringify(_StackMainSize));

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
    
    // Config watchdog timer:
    //   WDTPW:             password
    //   WDTSSEL__SMCLK:    watchdog source = SMCLK
    //   WDTTMSEL:          interval timer mode
    //   WDTCNTCL:          clear counter
    //   WDTIS__8192:       interval = SMCLK / 8192 Hz = 16MHz / 8192 = 1953.125 Hz => period=512 us
    WDTCTL = WDTPW | WDTSSEL__SMCLK | WDTTMSEL | WDTCNTCL | WDTIS__8192;
    SFRIE1 |= WDTIE; // Enable WDT interrupt
    
    _Scheduler::Run();
}

extern "C" [[noreturn]]
void abort() {
    _Pin::DEBUG_OUT::Init();
    for (bool x=0;; x=!x) {
        _Pin::DEBUG_OUT::Write(x);
    }
}
