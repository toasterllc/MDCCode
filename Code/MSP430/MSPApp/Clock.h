#pragma once
#include <msp430.h>
#include "GPIO.h"
#include "Code/Lib/Toastbox/Util.h"

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

template<typename T_Scheduler, uint32_t T_MCLKFreqHz, typename T_XINPin, typename T_XOUTPin>
class T_Clock {
public:
    struct Pin {
        using XIN  = typename T_XINPin::template Opts<GPIO::Option::Sel01>;
        using XOUT = typename T_XOUTPin::template Opts<GPIO::Option::Sel01>;
    };
    
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
            CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
            
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
        
        // Wait up to 2 seconds for XT1 to be ready.
        // The MSP430FR2433 datasheet claims 1s is typical for XT1 to start.
        for (uint16_t i=0; i<200 && _ClockFaults(); i++) {
            _ClockFaultsClear();
            T_Scheduler::Delay(_Ms<10>);
        }
        Assert(!_ClockFaults());
        
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
        
        // Decrease the XT1 drive strength to save a little current
        CSCTL6 =
            XT1DRIVE_0      |   // drive strength = lowest (to save current)
            (XTS&0)         |   // mode = low frequency
            (XT1BYPASS&0)   |   // bypass = disabled (ie XT1 source is an oscillator, not a clock signal)
            (XT1AGCOFF&0)   |   // automatic gain = on
            XT1AUTOOFF      ;   // auto off = enabled (default value)
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
    
    template<auto T>
    static constexpr auto _Ms = T_Scheduler::template Ms<T>;
    
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
            static_assert(Toastbox::AlwaysFalse_v<T_MCLKFreqHz>);
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
