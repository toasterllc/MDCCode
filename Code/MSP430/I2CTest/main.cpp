#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include <atomic>
#define TaskMSP430
#include "Toastbox/Task.h"
#include "Util.h"
#include "../MSPApp/Startup.h"
#include "../MSPApp/GPIO.h"
#include "../MSPApp/Clock.h"
#include "../MSPApp/I2C.h"
#include "../MSPApp/WDT.h"
using namespace GPIO;

#define Assert(x) if (!(x)) _MainError(__LINE__)
#define AssertArg(x) if (!(x)) _MainError(__LINE__)

static constexpr uint64_t _MCLKFreqHz       = 16000000;
static constexpr uint32_t _XT1FreqHz        = 32768;
static constexpr uint32_t _SysTickPeriodUs  = 512;

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line);

struct _Pin {
    using LED1      = PortA::Pin<0x0, Option::Output0>;
    using LED2      = PortA::Pin<0x1, Option::Output0>;
    using I2CData   = PortA::Pin<0x2>;
    using I2CClock  = PortA::Pin<0x3>;
};

using _Clock = ClockType<_MCLKFreqHz>;
using _SysTick = WDTType<_MCLKFreqHz, _SysTickPeriodUs>;
struct _I2CMsg {
    uint8_t type = 0;
    uint8_t payload = 0;
};

class _I2CTask;

static void _Sleep();

static void _MainError(uint16_t line);
static void _SchedulerError(uint16_t line);
static void _I2CError(uint16_t line);

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
    _I2CTask                                    // T_Tasks: list of tasks
>;

using _I2C = I2CType<_Scheduler, _Pin::I2CClock, _Pin::I2CData, _I2CMsg, _I2CError>;

struct _I2CTask {
    static void Run() {
        // Init I2C Peripheral
        _I2C::Init();
        
        for (;;) {
            // Wait for a message to arrive over I2C
            _I2CMsg msg;
            _I2C::Recv(msg);
            
            // Send a response
            _I2C::Send(msg);
            
//            _Pin::LED1::Write(1);
//            _Scheduler::Sleep(_Scheduler::Ms(1000));
//            _Pin::LED1::Write(0);
//            _Scheduler::Sleep(_Scheduler::Ms(1000));
        }
    }
    
    // Task options
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run, // Task should start running
    };
    
    // Task stack
    [[gnu::section(".stack._I2CTask")]]
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
    __bis_SR_register(GIE | LPM0_bits);
    // If interrupts were disabled previously, disable them again
    if (!prevEn) Toastbox::IntState::SetInterruptsEnabled(false);
}

// MARK: - Interrupts

[[gnu::interrupt(WDT_VECTOR)]]
static void _ISR_WDT() {
    const bool wake = _Scheduler::Tick();
    if (wake) {
        // Wake ourself
        __bic_SR_register_on_exit(LPM0_bits);
    }
}

[[gnu::interrupt(USCI_B0_VECTOR)]]
static void _ISR_USCI_B0() {
    _I2C::ISR();
    // Wake ourself
    __bic_SR_register_on_exit(LPM0_bits);
}

// MARK: - Abort

namespace AbortDomain {
    static constexpr uint16_t Invalid       = 0;
    static constexpr uint16_t Main          = 1;
    static constexpr uint16_t Scheduler     = 2;
    static constexpr uint16_t I2C           = 3;
}

[[noreturn]]
static void _MainError(uint16_t line) {
    _Abort(AbortDomain::Main, line);
}

[[noreturn]]
static void _SchedulerError(uint16_t line) {
    _Abort(AbortDomain::Scheduler, line);
}

[[noreturn]]
static void _I2CError(uint16_t line) {
    _Abort(AbortDomain::I2C, line);
}

[[noreturn]]
static void _Abort(uint16_t domain, uint16_t line) {
    for (;;);
}

extern "C" [[noreturn]]
void abort() {
    Assert(false);
}

// MARK: - Main

#define _StackMainSize 256

[[gnu::section(".stack.main")]]
uint8_t _StackMain[_StackMainSize];

asm(".global __stack");
asm(".equ __stack, _StackMain+" Stringify(_StackMainSize));

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIO::Init<
        _Pin::LED1,
        _Pin::LED2,
        _I2C::Pin::Clk,
        _I2C::Pin::Data
    >();
    
    // Init clock
    _Clock::Init();
    
    // Init SysTick
    _SysTick::Init();
    
    _Scheduler::Run();
}
