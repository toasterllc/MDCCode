#include <msp430.h>
#include "GPIO.h"
#include "Assert.h"
#include "Startup.h"
#include "Toastbox/Util.h"
#include "Toastbox/Scheduler.h"
using namespace GPIO;

struct _Pin {
    using LED1      = PortA::Pin<0x0, Option::Output0>;
    using LED2      = PortA::Pin<0x1, Option::Output0, Option::Sel10>;
};

// Abort(): called by Assert() with the address that aborted
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr) {
    for (;;);
}

// MARK: - _TaskMain

#define _TaskMainStackSize 128

SchedulerStack(".stack._TaskMain")
uint8_t _TaskMainStack[_TaskMainStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskMainStack+" Stringify(_TaskMainStackSize));

template<uint32_t T_MCLKFreqHz>
class T_Clock {
public:
    // Init(): initialize various clocks
    // Interrupts must be disabled
    static void Init() {
        // Configure one FRAM wait state if MCLK > 8MHz.
        // This must happen before configuring the clock system.
        if constexpr (T_MCLKFreqHz > 8000000) {
            FRCTL0 = FRCTLPW | NWAITS_1;
        }
        
        // Disable FLL
        __bis_SR_register(SCG0);
            // FLLREFCLK=REFOCLK, FLLREFDIV=/1
            CSCTL3 = SELREF__REFOCLK | FLLREFDIV_0;
            // Clear DCO and MOD registers
            CSCTL0 = 0;
            // Set CSCTL1
            CSCTL1 = _CSCTL1();
            // Set DCOCLKDIV based on T_MCLKFreqHz and _REFOCLKFreqHz
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/_REFOCLKFreqHz)-1);
            // Wait 3 cycles to take effect
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
        // Wait for FLL to lock
        // We can't use T_Scheduler::Delay() here because it calls our Sleep(), which stops the FLL,
        // and we need the FLL to be running to acquire a lock.
        while (!_FLLLocked());
        
        // MCLK=DCOCLK, ACLK=REFOCLK
        CSCTL4 = SELMS__DCOCLKDIV | SELA__REFOCLK;
    }
    
private:
    static constexpr uint32_t _REFOCLKFreqHz = 32768;
    static constexpr uint16_t _CSCTL1Default = DCOFTRIM_3 | DISMOD;
    
    static constexpr uint16_t _CSCTL1() {
               if constexpr (T_MCLKFreqHz == 16000000) {
            return DCORSEL_5 | _CSCTL1Default;
        } else if constexpr (T_MCLKFreqHz == 12000000) {
            return DCORSEL_4 | _CSCTL1Default;
        } else if constexpr (T_MCLKFreqHz == 8000000) {
            return DCORSEL_3 | _CSCTL1Default;
        } else if constexpr (T_MCLKFreqHz == 4000000) {
            return DCORSEL_2 | _CSCTL1Default;
        } else if constexpr (T_MCLKFreqHz == 2000000) {
            return DCORSEL_1 | _CSCTL1Default;
        } else if constexpr (T_MCLKFreqHz == 1000000) {
            return DCORSEL_0 | _CSCTL1Default;
        } else {
            // Unsupported frequency
            static_assert(Toastbox::AlwaysFalse<T_MCLKFreqHz>);
        }
    }
    
    static bool _FLLLocked() {
        return !(CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
    }
};


static constexpr uint32_t _MCLKFreqHz       = 16000000;     // 16 MHz
using _Clock = T_Clock<_MCLKFreqHz>;


inline bool Toastbox::IntState::Get() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::Set(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

int main() {
    WDTCTL = WDTPW | WDTHOLD;
    
    _Clock::Init();
    
    GPIO::Init<
        _Pin::LED1,
        _Pin::LED2
    >(Startup::ColdStart());
    
    
    
    // Additional clock divider = /3
    TA0EX0 = TAIDEX_2;
    TA0CCR1 = 65535-1;
    TA0CCR0 = 65535-0;
    
    // Start timer
    // Note that this clears TAIFG in case it was set!
    TA0CTL =
        TASSEL__ACLK    |   // clock source = ACLK
        ID__1           |   // clock divider = /1
        MC__UP          |   // mode = up
        TACLR           ;   // reset timer state
    
    TA0CCTL1 = OUTMOD_3;
    
    __bis_SR_register(GIE | LPM3_bits);
    for (;;);
    
//    for (;;) {
//        if (!_Pin::BUTTON::Read()) {
//            _Pin::LED1::Write(!_Pin::LED1::Read());
//        }
////        __bis_SR_register(GIE | LPM3_bits);
//    }
}
