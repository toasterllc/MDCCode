#pragma once
#include <msp430.h>
#include "GPIO.h"
#include "Toastbox/Util.h"

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
            // Set REFO as FLL reference source
            CSCTL3 |= SELREF__REFOCLK;
            // Clear DCO and MOD registers
            CSCTL0 = 0;
            // Clear DCO frequency select bits first
            CSCTL1 &= ~(DCORSEL_7);
            
            if constexpr (T_MCLKFreqHz == 16000000) {
                CSCTL1 |= DCORSEL_5;
            } else if constexpr (T_MCLKFreqHz == 12000000) {
                CSCTL1 |= DCORSEL_4;
            } else if constexpr (T_MCLKFreqHz == 8000000) {
                CSCTL1 |= DCORSEL_3;
            } else if constexpr (T_MCLKFreqHz == 4000000) {
                CSCTL1 |= DCORSEL_2;
            } else if constexpr (T_MCLKFreqHz == 2000000) {
                CSCTL1 |= DCORSEL_1;
            } else if constexpr (T_MCLKFreqHz == 1000000) {
                CSCTL1 |= DCORSEL_0;
            } else {
                // Unsupported frequency
                static_assert(Toastbox::AlwaysFalse<T_MCLKFreqHz>);
            }
            
            // Set DCOCLKDIV based on T_MCLKFreqHz and REFOCLKFreqHz
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/REFOCLKFreqHz)-1);
            
            // Special case: use the factory-calibrated values for CSCTL0 if one is available for the target frequency
            // This significantly speeds up the FLL lock time; without this technique, it takes ~200ms to get an FLL
            // lock (datasheet specifies 280ms as typical). Using the factory-calibrated value, an FLL lock takes 800us.
            if constexpr (T_MCLKFreqHz == 16000000) {
                CSCTL0 = *CSCTL0Cal16MHz;
            }
            
            // Wait 3 cycles to take effect
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
        // Special case: if we're using one of the factory-calibrated values for CSCTL0 (see above),
        // we need to delay 10 REFOCLK cycles. We do this by temporarily switching MCLK to be sourced
        // by REFOCLK, and waiting 10 cycles.
        // This technique is prescribed by "MSP430FR2xx/FR4xx DCO+FLL Applications Guide", and shown
        // by the "MSP430FR2x5x_FLL_FastLock_24MHz-16MHz.c" example code.
        if constexpr (T_MCLKFreqHz == 16000000) {
            CSCTL4 = SELMS__REFOCLK | SELA__REFOCLK;
            __delay_cycles(10);
        }
        
        // Wait until FLL locks
        while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
        
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
        
        // Turn on XT1 (by disabling XT1 auto-off, so we can get XT1 running without any
        // peripherals requesting it).
        // We don't need auto-off anyway because RTC needs XT1 to always be running to keep
        // track of time.
        CSCTL6 =
            XT1DRIVE_3      |   // drive strength = highest
            (XTS&0)         |   // mode = low frequency
            (XT1BYPASS&0)   |   // bypass = disabled (ie XT1 source is an oscillator, not a clock signal)
            (XT1AGCOFF&0)   |   // automatic gain = on
            (XT1AUTOOFF&0)  ;   // auto off = disabled (ie keep XT1 on)
        
//        // Wait up to 2 seconds for XT1 to start
//        // The MSP430FR2433 datasheet claims 1s is typical
//        for (uint16_t i=0; i<20 && _ClockFaults(); i++) {
//            _ClockFaultsClear();
//            T_Scheduler::Delay(_Ms<100>);
//        }
//        Assert(!_ClockFaults());
        
        // Wait up to 2 seconds for XT1 to start
        // The MSP430FR2433 datasheet claims 1s is typical
        while (_ClockFaults()) {
            _ClockFaultsClear();
//            T_Scheduler::Delay(_Ms<100>);
        }
        Assert(!_ClockFaults());
        
        // Now that we've cleared the oscillator faults, enable the oscillator fault interrupt
        // so we know if something goes awry in the future. This will call our ISR and we'll
        // record the failure and trigger a BOR.
        SFRIFG1 |= OFIE;
        
        // Decrease the XT1 drive strength to save a little current
        CSCTL6 = (CSCTL6 & ~(XT1DRIVE0|XT1DRIVE1)) | XT1DRIVE_0;
        
        // Switch MCLK and ACLK to their final sources
        // MCLK / SMCLK source = DCOCLKDIV
        //         ACLK source = XT1CLK
        CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
    }
    
private:
    static constexpr uint32_t REFOCLKFreqHz = 32768;
    
    template<auto T>
    static constexpr auto _Ms = T_Scheduler::template Ms<T>;
    
    static void _ClockFaultsClear() {
        CSCTL7 &= ~(XT1OFFG | DCOFFG);
        SFRIFG1 &= ~OFIFG;
    }
    
    static bool _ClockFaults() {
        return SFRIFG1 & OFIFG;
    }
};
