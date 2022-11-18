#pragma once
#include <msp430.h>
#include "GPIO.h"

template <uint32_t T_MCLKFreqHz>
class ClockType {
public:
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
                static_assert(_AlwaysFalse<T_MCLKFreqHz>);
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
            CSCTL4 |= SELMS__REFOCLK;
            __delay_cycles(10);
        }
        
        // Wait until FLL locks
        while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
        
        // MCLK / SMCLK source = DCOCLKDIV
        //         ACLK source = XT1
        CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
    }

private:
    static constexpr uint32_t REFOCLKFreqHz = 32768;
    template <class...> static constexpr std::false_type _AlwaysFalse = {};
};
