#pragma once
#include <msp430.h>
#include "GPIO.h"

template <uint32_t T_XT1FreqHz, uint32_t T_MCLKFreqHz, typename T_XOUTPin, typename T_XINPin>
class ClockType {
public:
    struct Pin {
        using XOUT  = typename T_XOUTPin::template Opts<GPIO::Option::Sel10>;
        using XIN   = typename T_XINPin::template Opts<GPIO::Option::Sel10>;
    };
    
    static void Init() {
//        const uint16_t* CSCTL0Cal16MHz = (uint16_t*)0x1A22;
        
        // Configure one FRAM wait state if MCLK > 8MHz.
        // This must happen before configuring the clock system.
        if constexpr (T_MCLKFreqHz > 8000000) {
            FRCTL0 = FRCTLPW | NWAITS_1;
        }
        
        do {
            CSCTL7 &= ~(XT1OFFG | DCOFFG); // Clear XT1 and DCO fault flag
            SFRIFG1 &= ~OFIFG;
        } while (SFRIFG1 & OFIFG); // Test oscillator fault flag
        
        // Disable FLL
        __bis_SR_register(SCG0);
            // Set XT1 as FLL reference source
            CSCTL3 |= SELREF__XT1CLK;
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
                static_assert(_AlwaysFalse<T_MCLKFreqHz>);
            }
            
            // Set DCOCLKDIV based on T_MCLKFreqHz and T_XT1FreqHz
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/T_XT1FreqHz)-1);
            
//            // Special case: use the factory-calibrated values for CSCTL0 if one is available for the target frequency
//            // This significantly speeds up the FLL lock time; without this technique, it takes ~200ms to get an FLL
//            // lock (datasheet specifies 280ms as typical). Using the factory-calibrated value, an FLL lock takes 800us.
//            if constexpr (T_MCLKFreqHz == 16000000) {
//                CSCTL0 = *CSCTL0Cal16MHz;
//            }
            
            // Wait 3 cycles to take effect
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
//        // Special case: if we're using one of the factory-calibrated values for CSCTL0 (see above),
//        // we need to delay 10 REFOCLK cycles. We do this by temporarily switching MCLK to be sourced
//        // by REFOCLK, and waiting 10 cycles.
//        // This technique is prescribed by "MSP430FR2xx/FR4xx DCO+FLL Applications Guide", and shown
//        // by the "MSP430FR2x5x_FLL_FastLock_24MHz-16MHz.c" example code.
//        if constexpr (T_MCLKFreqHz == 16000000) {
//            CSCTL4 |= SELMS__REFOCLK;
//            __delay_cycles(10);
//        }
        
        // Wait until FLL locks
        while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
        
        // MCLK / SMCLK source = DCOCLKDIV
        //         ACLK source = XT1
        CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
        
        // Decrease the XT1 drive strength to save a little current
        // We're not using this for now because supporting it with LPM3.5 is gross.
        // That's because on a cold start, CSCTL6.XT1DRIVE needs to be set after we
        // clear LOCKLPM5 (to reduce the drive strength after XT1 is running),
        // but on a warm start, CSCTL6.XT1DRIVE needs to be set before we clear
        // LOCKLPM5 (to return the register to its previous state before unlocking).
        CSCTL6 = (CSCTL6 & ~XT1DRIVE) | XT1DRIVE_0;
        
        // Clear SMCLKREQEN so peripherals don't get to assert that SMCLK is enabled.
        // This allows us to enter LPM3 for 'deep sleep'.
        CSCTL8 &= ~SMCLKREQEN;
    }

private:
    template <class...> static constexpr std::false_type _AlwaysFalse = {};
};
