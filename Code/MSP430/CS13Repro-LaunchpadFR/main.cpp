#include <msp430.h>
#include "GPIO.h"
#include "Assert.h"
#include "Toastbox/Util.h"
using namespace GPIO;

struct _Pin {
    using LED1      = PortA::Pin<0x0, Option::Output0>;
    using INT       = PortA::Pin<0x1, Option::Interrupt10>; // P1.1
    using MCLK      = PortA::Pin<0x3, Option::Output0, Option::Sel10>; // P1.3 (MCLK)
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

#pragma once
#include <msp430.h>
#include "GPIO.h"
#include "Toastbox/Util.h"

// DCO / FLL operation:
//     f_DCOCLK is directly controlled by: CSCTL0.MOD, CSCTL0.DCO, CSCTL1.DCORSEL
//     
//     The FLL target frequency is controlled by: CSCTL2.FLLD / CSCTL2.FLLN / CSCTL3.FLLREFDIV
//     
//     When FLL is enabled (SCG0=1), CSCTL0.MOD, CSCTL0.DCO is controlled by FLL,
//     thereby allowing FLL to control f_DCOCLK.
//     
//     When FLL is disabled (SCG0=0), CSCTL0.MOD CSCTL0.DCO is not controlled by FLL,
//     and is under manual control

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
                CSCTL0 = _CSCTL0Compensate(*CSCTL0Cal16MHz);
            } else {
                CSCTL0 = 0;
            }
            
            // Set the frequency range, CSCTL1.DCORSEL
            CSCTL1 = _CSCTL1();
            
            // Configure FLL via CSCTL2.FLLD, CSCTL2.FLLN
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/_REFOCLKFreqHz)-1);
            
            // MCLK=DCOCLK, ACLK=XT1
            CSCTL4 = SELMS__DCOCLKDIV | SELA__REFOCLK;
            
            // "Execute NOP three times to allow time for the settings to be applied."
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
        // Wait for FLL to lock
        //
        // Delay 10 REFOCLK cycles before polling _FLLLocked, to avoid getting a false _FLLLocked() reading
        // from the previous FLL settings.
        //
        // We can't use T_Scheduler::Delay() here because it calls our Sleep(), which stops the FLL, and we
        // need the FLL to be running to acquire a lock.
        __delay_cycles(10*(T_MCLKFreqHz/_REFOCLKFreqHz));
        while (!_FLLLocked());
        
        // Cache _CSCTL0Compensated now that the FLL has locked, so we can get good reading of CSCTL0.
        // We cache a compensated value (see _CSCTL0Compensate() comments) so we can set CSCTL0 directly
        // to it, without having to perform math on it on every use.
        _CSCTL0Compensated = _CSCTL0Compensate(CSCTL0);
        
        while (_ClockFaults()) _ClockFaultsClear();
        
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
        SFRIE1 |= OFIE;
    }
    
    /// Sleep(): sleep either for a short or long period.
    ///
    /// For short sleeps (extended=0): we assume the DCO settings (CSCTL0.DCO
    /// and CSCTL0.MOD) will remain valid for the target frequency when we wake.
    ///
    /// For long sleeps (extended=1): we assume the DCO settings (CSCTL0.DCO
    /// and CSCTL0.MOD) will become invalid while we sleep, because the
    /// temperature or voltage may change significantly while we sleep.
    /// Therefore we set CSCTL0=_CSCTL0Compensated before we sleep, which sets
    /// CSCTL0.DCO and CSCTL0.MOD to conservative versions of their original
    /// values that were captured when we first turned on. The effect is that
    /// before an extended sleep, we run at a slightly slower frequency than
    /// the target frequency (eg 15 MHz instead of the target 16 MHz). Note
    /// that interrupts are also handled at this slower frequency because the
    /// FLL remains disabled while handling interrupts.
    ///
    /// *** Errata CS13 Note ***
    /// Errata CS13 states:
    /// 
    ///   Device may enter lockup state during transition from AM to LPM3/4 if DCO frequency is
    ///   above 2 MHz.
    /// 
    /// We asked TI for details and they sent us Errata-CS13.pptx (see MDCNotes repo). We were
    /// able to reproduce the CS13 issue using the described setup, and determined that the
    /// issue isn't reproducible for VDD > 2.1V, so we haven't implemented the prescribed
    /// workaround since our VDD will always be >3V.
    ///
    static void Sleep(bool extended) {
        // If this is an extended sleep, decrease our clock frequency slightly by
        // using CSCTL0Compensated.
        if (extended) {
            // Disable FLL
            __bis_SR_register(SCG0);
            CSCTL0 = _CSCTL0Compensated;
        }
        
        // Sleep
        {
            Toastbox::IntState ints; // Remember+restore current interrupt state
            __bis_SR_register(GIE | LPM3_bits); // Sleep
        }
    }
    
    [[gnu::always_inline]] // Necessary because result needs to be stored in a register
    static void Wake() {
        // Wake from sleep
        __bic_SR_register_on_exit(LPM3_bits);
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
};



static constexpr uint32_t _MCLKFreqHz       = 16000000;     // 16 MHz
using _Clock = T_Clock<_MCLKFreqHz>;

[[gnu::interrupt]]
void _ISR_PORT1() {
    switch (P1IV) {
    case _Pin::INT::IVPort1():
        __delay_cycles(16000000);
        _Clock::Wake();
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
        _Pin::LED1,
        _Pin::INT,
        _Pin::MCLK
    >();
    
//    for (int i=0; i<5; i++) {
//        __delay_cycles(16000000);
//    }
    
    for (;;) {
        _Clock::Sleep(true);
        _Pin::LED1::Write(!_Pin::LED1::Read());
        __delay_cycles(16000000);
    }
    
//    for (;;) {
//        if (!_Pin::BUTTON::Read()) {
//            _Pin::LED1::Write(!_Pin::LED1::Read());
//        }
////        __bis_SR_register(GIE | LPM3_bits);
//    }
}
