#pragma once
#include <msp430.h>
#include "GPIO.h"

template <uint32_t T_MCLKFreqHz>
class ClockType {
public:
    static void Init() {
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
                static_assert(_AlwaysFalse<T_MCLKFreqHz>);
            }
            
            // Set DCOCLKDIV based on T_MCLKFreqHz and REFOCLKFreqHz
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/REFOCLKFreqHz)-1);
            
            // Wait 3 cycles to take effect
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
        // Wait until FLL locks
        while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
        
        // MCLK / SMCLK source = DCOCLKDIV
        //         ACLK source = REFOCLK
        CSCTL4 = SELMS__DCOCLKDIV | SELA__REFOCLK;
    }

private:
    static constexpr uint32_t REFOCLKFreqHz = 32768;
    template <class...> static constexpr std::false_type _AlwaysFalse = {};
};
