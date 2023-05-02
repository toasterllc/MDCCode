#include <msp430.h>
#include "GPIO.h"
#include "Assert.h"
#include "Toastbox/Util.h"
using namespace GPIO;

struct _Pin {
    using LEDRED    = PortA::Pin<0x0, Option::Output0>;
    using LEDGREEN  = PortA::Pin<0x1, Option::Output0>;
    using BUTTON    = PortA::Pin<0xF, Option::Resistor1, Option::Interrupt10>;
    using INT       = PortA::Pin<0x1, Option::Interrupt01>; // P1.1
    using MCLK      = PortA::Pin<0x3, Option::Output0, Option::Sel10>; // P1.3 (MCLK)
};

// Abort(): called by Assert() with the address that aborted
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr) {
    Toastbox::IntState ints(false);
    for (;;);
}

// MARK: - _TaskMain

#define _TaskMainStackSize 128

SchedulerStack(".stack._TaskMain")
uint8_t _TaskMainStack[_TaskMainStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskMainStack+" Stringify(_TaskMainStackSize));

#pragma once
#include <msp430.h>
#include "GPIO.h"
#include "Toastbox/Util.h"

template<uint32_t T_MCLKFreqHz>
class T_Clock {
public:
    // Init(): initialize various clocks
    // Interrupts must be disabled
    static void Init() {
        const uint16_t*const CSCTL0Cal16MHz = (uint16_t*)0x1A22;
        
        // Configure one FRAM wait state if MCLK > 8MHz.
        // This must happen before configuring the clock system.
        if constexpr (T_MCLKFreqHz > 8000000) {
            FRCTL0 = FRCTLPW | NWAITS_1;
        }
        
        // Disable FLL
        __bis_SR_register(SCG0);
            // FLLREFCLK=REFOCLK, FLLREFDIV=/1
            CSCTL3 = SELREF__REFOCLK | FLLREFDIV_0;
            
            // Clear CSCTL0.DCO and CSCTL0.MOD so we start out at the lowest tap within CSCTL1.DCORSEL,
            // when we set CSCTL1.DCORSEL on the next line. This is necessary to prevent overshoot,
            // since the current value of CSCTL0.DCO/CSCTL0.MOD pertains to the whatever value of
            // CSCTL1.DCORSEL we currently have set, and not the value we're about to set.
            //
            // Special case: use the factory-calibrated values for CSCTL0 if one is available for the
            // target frequency. This significantly speeds up the FLL lock time; without this technique,
            // it takes ~200ms to get an FLL lock (datasheet specifies 280ms as typical). Using the
            // factory-calibrated value, an FLL lock takes 800us.
            if constexpr (T_MCLKFreqHz == 16000000) {
                CSCTL0 = *CSCTL0Cal16MHz;
            } else {
                CSCTL0 = 0;
            }
            
            // Set the frequency range, CSCTL1.DCORSEL
            CSCTL1 = _CSCTL1();
            
            // Configure FLL via CSCTL2.FLLD, CSCTL2.FLLN
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/_REFOCLKFreqHz)-1);
            
            // MCLK=DCOCLK, ACLK=REFOCLK
            CSCTL4 = SELMS__DCOCLKDIV | SELA__REFOCLK;
            
            // "Execute NOP three times to allow time for the settings to be applied."
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
        // Wait for FLL to lock
        // We can't use T_Scheduler::Delay() here because it calls our Sleep(), which stops the FLL,
        // and we need the FLL to be running to acquire a lock.
        while (!_FLLLocked());
        
        // Set MCLK/SMCLK dividers
        //
        // If we ever change DIVS to something other than DIVS__1, we may be subject to errata
        // PMM32 ("Device may enter lockup state or execute unintentional code during transition
        // from AM to LPM3/4"), due to Condition2.4 ("SMCLK is configured with a different
        // frequency than MCLK").
        //
        // We're not setting CSCTL5 because its default value is what we want.
        //
        // CSCTL5 = VLOAUTOOFF | (SMCLKOFF&0) | DIVS__1 | DIVM__1;
        
        // Now that we've cleared the oscillator faults, enable the oscillator fault interrupt
        // so we know if something goes awry in the future. This will call our ISR and we'll
        // record the failure and trigger a BOR.
//        SFRIE1 |= OFIE;
        
        // Decrease the XT1 drive strength to save a little current
        CSCTL6 =
            XT1DRIVE_0      |   // drive strength = lowest (to save current)
            (XTS&0)         |   // mode = low frequency
            (XT1BYPASS&0)   |   // bypass = disabled (ie XT1 source is an oscillator, not a clock signal)
            (XT1AGCOFF&0)   |   // automatic gain = on
            XT1AUTOOFF      ;   // auto off = enabled (default value)
    }
    
private:
    static constexpr uint32_t _REFOCLKFreqHz = 32768;
    static constexpr uint16_t _CSCTL1Default = DCOFTRIM_3 | DISMOD;
    static inline uint16_t _CSCTL0Compensated = 0;
    
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
    
    // _CSCTL0Compensate(): compensate the given `CSCTL0` value for temperature
    // and voltage variation that could occur during sleep. In our testing, warming
    // the chip with hot air (~300 C) for a few seconds caused a CSCTL0.DCO to
    // decrease by 19 counts, so we figured that 64 is a good conservative value.
    static constexpr uint16_t _CSCTL0Compensate(uint16_t x) {
        constexpr uint16_t Sub = 64;
        const uint16_t dco = x & 0x1FF;
        return (dco>Sub ? dco-Sub : 1);
    }
    
//    static void _SleepEnable() {
//        // Disable FLL
//        __bis_SR_register(SCG0);
//        // Config DCO for 2MHz band
//        // This is necessary for Errata CS13:
//        //   Device may enter lockup state during transition from AM to LPM3/4
//        //   if DCO frequency is above 2 MHz.
//        CSCTL1 = DCORSEL_1 | _CSCTL1Default;
//        // Wait 3 cycles to take effect
//        __delay_cycles(3);
//    }
//    
//    static void _SleepDisable() {
//        // Restore the target frequency band (CSCTL1.DCORSEL)
//        CSCTL1 = _CSCTL1();
//        // Enable FLL
//        __bic_SR_register(SCG0);
//    }
//    
//    static constexpr uint16_t _CSCTL5(bool fast=false) {
//        static constexpr Default = VLOAUTOOFF | (SMCLKOFF&0) | DIVS__1;
//        if (fast) return Default | DIVM__1;
//        else      return Default | DIVM__2;
//    }
    
    static bool _FLLLocked() {
        return !(CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
    }
    
    static void _ClockFaultsClear() {
        CSCTL7 &= ~(XT1OFFG | DCOFFG);
        SFRIFG1 &= ~OFIFG;
    }
    
    static bool _ClockFaults() {
        return SFRIFG1 & OFIFG;
    }
    
//    static bool _ClockReady() {
//        const bool faults = SFRIFG1 & OFIFG;
//        const bool fllLocked = !(CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
//        return !faults && fllLocked;
//    }
};


static constexpr uint32_t _MCLKFreqHz = 16000000;     // 16 MHz
using _Clock = T_Clock<_MCLKFreqHz>;

[[gnu::interrupt]]
void _ISR_PORT1() {
    switch (P1IV) {
    case _Pin::INT::IVPort1():
//        __bic_SR_register_on_exit(LPM3_bits);
        __bic_SR_register_on_exit(GIE | LPM3_bits);
        break;
    default:
        Assert(false);
    }
}

[[gnu::interrupt]]
void _ISR_PORT2() {
    switch (P2IV) {
    case _Pin::BUTTON::IVPort2():
//        __bic_SR_register_on_exit(LPM3_bits);
        __bic_SR_register_on_exit(GIE | LPM3_bits);
        break;
    default:
        Assert(false);
    }
}

[[gnu::interrupt]]
void _ISR_TIMER0_A1() {
    switch (TA0IV) {
    case TA0IV_TAIFG:
        __bic_SR_register_on_exit(GIE | LPM3_bits);
//        static uint16_t counter = 0;
//        counter++;
//        if (counter == 5000) {
//            counter = 0;
//            __bic_SR_register_on_exit(GIE | LPM3_bits);
//            
////            _Pin::LEDRED::Write(!_Pin::LEDRED::Read());
//            
////        __bic_SR_register_on_exit(LPM3_bits);
//////        __bic_SR_register_on_exit(GIE | LPM3_bits);
//            
//        }
        break;
    default:
        Assert(false);
    }
}

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
        _Pin::LEDRED,
        _Pin::LEDGREEN,
        _Pin::BUTTON,
        _Pin::INT,
        _Pin::MCLK
    >();
    
//    __bis_SR_register(GIE | LPM3_bits);
//    for (;;);
    
//    for (;;) {
//        if (!_Pin::BUTTON::Read()) {
//            _Pin::LEDRED::Write(!_Pin::LEDRED::Read());
//        }
////        __bis_SR_register(GIE | LPM3_bits);
//    }
    
    
//    for (;;) {
//        _Pin::LEDRED::Write(!_Pin::LEDRED::Read());
//        __bis_SR_register(GIE | LPM3_bits);
//    }
    
//    // Overclock ourself
//    __bis_SR_register(SCG0); // Disable FLL
//    const uint16_t dco = CSCTL0 & 0x1FF;
//    CSCTL0 &= ~0x1FF;
//    CSCTL0 |= dco+128;
    
    TA0EX0 = 0;
    TA0CCR0 = 1;
    TA0CTL =
        TASSEL__ACLK    |   // clock source = ACLK
        ID__1           |   // clock divider = /8
        MC__UPDOWN      |   // mode = up
        TACLR           |   // reset timer state
        TAIE            ;   // enable interrupt
    
    uint16_t counter = 0;
    for (;;) {
        __bis_SR_register(GIE | LPM3_bits);
        counter++;
        if (counter == 5000) {
            _Pin::LEDRED::Write(!_Pin::LEDRED::Read());
            counter = 0;
        }
    }
    
    _Pin::LEDGREEN::Write(1);
    for (;;);
    
//    for (;;) {
//        _Pin::LEDRED::Write(!_Pin::LEDRED::Read());
//        __delay_cycles(1000000);
//        _Clock::Sleep();
//    }
}
