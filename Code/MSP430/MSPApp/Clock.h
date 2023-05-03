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
        const uint16_t* CSCTL0Cal16MHz = (uint16_t*)0x1A22;
        
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
            CSCTL0 = 0;
            
            // Set the frequency range, CSCTL1.DCORSEL
            CSCTL1 = _CSCTL1();
            
            // Configure FLL via CSCTL2.FLLD, CSCTL2.FLLN
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/_REFOCLKFreqHz)-1);
            
            // Special case: use the factory-calibrated values for CSCTL0 if one is available for the
            // target frequency. This significantly speeds up the FLL lock time; without this technique,
            // it takes ~200ms to get an FLL lock (datasheet specifies 280ms as typical). Using the
            // factory-calibrated value, an FLL lock takes 800us.
            //
            // We switch MCLK=REFOCLK before setting CSCTL0, so that MCLK isn't sourced from DCOCLKDIV
            // while FLL is acquiring a lock, because during this time the FLL may overshoot the target
            // frequency, which could violate the MCLK max frequency. This is only an issue when using
            // calibrated CSCTL0 values because we use 0 otherwise, which is the minimum value for a
            // CSCTL1.DCORSEL range so we don't have to worry about overshoot.
            if constexpr (T_MCLKFreqHz == 16000000) {
                CSCTL4 = SELMS__REFOCLK | SELA__REFOCLK;
                CSCTL0 = *CSCTL0Cal16MHz;
            }
            
            // "Execute NOP three times to allow time for the settings to be applied."
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
        // Special case: if we're using one of the factory-calibrated values for CSCTL0 (see above),
        // we need to delay 10 FLL reference clock cycles. We do this by temporarily switching MCLK
        // to be sourced by REFOCLK (performed above), and waiting 10 cycles.
        // This delay is prescribed by "MSP430FR2xx/FR4xx DCO+FLL Applications Guide", and shown by
        // the "MSP430FR2x5x_FLL_FastLock_24MHz-16MHz.c" example code.
        if constexpr (T_MCLKFreqHz == 16000000) {
            __delay_cycles(10);
        }
        
        // Wait until FLL locks
        while (!_FLLLocked());
        
        // MCLK=DCOCLK, ACLK=XT1
        CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
        
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
        
        // Wait up to 2 seconds for XT1 to start
        // The MSP430FR2433 datasheet claims 1s is typical
        for (uint16_t i=0; i<20 && _ClockFaults(); i++) {
            _ClockFaultsClear();
            T_Scheduler::Delay(_Ms<100>);
        }
        Assert(!_ClockFaults());
        
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
    
    // Sleep(): sleep either for a short or long period.
    //
    // For short sleeps (extended=0): we assume the DCO settings (CSCTL0.DCO
    // and CSCTL0.MOD) will remain valid for the target frequency when we wake.
    //
    // For long sleeps (extended=1): we assume the DCO settings (CSCTL0.DCO
    // and CSCTL0.MOD) will be invalid when we wake, because the temperature
    // or voltage may have changed significantly while we slept.
    //
    // If the FLL is currently locked, we cache the current value of CSCTL0
    // so that we can use it on subsequent wakes to speed up the FLL lock.
    //
    // Note that we compensate the cached CSCTL0 for temperature or voltage
    // variations during sleep, that could otherwise cause the FLL to
    // overshoot its target frequency if we used the value directly.
    static void Sleep(bool extended) {
        static uint16_t CSCTL0Compensated = 0;
        if (extended && _FLLLocked()) CSCTL0Compensated = _CSCTL0Compensate(CSCTL0);
        
        // Switch to 2MHz
        {
            // Disable FLL
            __bis_SR_register(SCG0);
            // Config DCO for 2MHz band
            // This is necessary for Errata CS13:
            //   Device may enter lockup state during transition from AM to LPM3/4
            //   if DCO frequency is above 2 MHz.
            CSCTL1 = DCORSEL_1 | _CSCTL1Default;
            // Wait 3 cycles to take effect
            __delay_cycles(3);
        }
        
        // Sleep
        {
            Toastbox::IntState ints; // Remember+restore current interrupt state
            __bis_SR_register(GIE | LPM3_bits); // Sleep
        }
        
        // Restore CSCTL0 to CSCTL0Compensated before switching back to fast clock
        if (extended) CSCTL0 = CSCTL0Compensated;
        
        // Switch back to T_MCLKFreqHz
        {
            // Restore the target frequency band (CSCTL1.DCORSEL)
            CSCTL1 = _CSCTL1();
            // Enable FLL
            __bic_SR_register(SCG0);
        }
    }
    
    [[gnu::always_inline]] // Necessary because result needs to be stored in a register
    static void Wake() {
        // Wake from sleep, but don't start FLL yet
        __bic_SR_register_on_exit(LPM3_bits & ~SCG0);
    }
    
private:
    static constexpr uint32_t _REFOCLKFreqHz = 32768;
    static constexpr uint16_t _CSCTL1Default = DCOFTRIM_3 | DISMOD;
//    static constexpr uint16_t _CSCTL0Max = 0x3FFF;
    
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
            static_assert(Toastbox::AlwaysFalse<T_MCLKFreqHz>);
        }
    }
    
    // _CSCTL0Compensate(): compensate the given `CSCTL0` value for temperature
    // and voltage variation that could occur during sleep. In our testing, warming
    // the chip with hot air (~300 C) for a few seconds caused a CSCTL0.DCO to
    // decrease by 19 counts, so we figured that 64 is a good conservative value.
    static uint16_t _CSCTL0Compensate(uint16_t x) {
        constexpr uint16_t Sub = 64;
        const uint16_t dco = x & 0x1FF;
        return (dco>=Sub ? dco-Sub : 0);
    }
    
    static bool _FLLLocked() {
        return !(CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
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
    
    static void _ClockFaultsClear() {
        CSCTL7 &= ~(XT1OFFG | DCOFFG);
        SFRIFG1 &= ~OFIFG;
    }
    
    static bool _ClockFaults() {
        return SFRIFG1 & OFIFG;
    }
};
