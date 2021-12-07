#pragma once
#include <msp430.h>

template <uint32_t T_XT1FreqHz, uint32_t T_MCLKFreqHz, typename T_XOUTPin, typename T_XINPin>
class ClockType {
public:
    struct Pin {
        using XOUT  = typename T_XOUTPin::template Opts<GPIO::Option::Sel10>;
        using XIN   = typename T_XINPin::template Opts<GPIO::Option::Sel10>;
    };
    
    static void Init() {
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
                static_assert(_AlwaysFalse<T_MCLKFreqHz>);
            }
            
            // Set DCOCLKDIV based on T_MCLKFreqHz and T_XT1FreqHz
            CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/T_XT1FreqHz)-1);
            
            // Wait 3 cycles to take effect
            __delay_cycles(3);
        // Enable FLL
        __bic_SR_register(SCG0);
        
        // Wait until FLL locks
        while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
        
        // MCLK / SMCLK source = DCOCLKDIV
        // ACLK source = XT1
        CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
    }

private:
    template <class...> static constexpr std::false_type _AlwaysFalse = {};
};
