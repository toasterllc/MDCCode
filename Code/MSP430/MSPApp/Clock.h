#pragma once
#include <msp430.h>

template <uint32_t XT1FreqHz, uint32_t MCLKFreqHz>
class ClockType {
public:
    static void Init() {
        // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
        // This must happen before configuring the clock system.
        FRCTL0 = FRCTLPW | NWAITS_1;
        
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
            
            if constexpr (MCLKFreqHz == 16000000) {
                CSCTL1 |= DCORSEL_5;
            } else if constexpr (MCLKFreqHz == 12000000) {
                CSCTL1 |= DCORSEL_4;
            } else if constexpr (MCLKFreqHz == 8000000) {
                CSCTL1 |= DCORSEL_3;
            } else if constexpr (MCLKFreqHz == 4000000) {
                CSCTL1 |= DCORSEL_2;
            } else if constexpr (MCLKFreqHz == 2000000) {
                CSCTL1 |= DCORSEL_1;
            } else if constexpr (MCLKFreqHz == 1000000) {
                CSCTL1 |= DCORSEL_0;
            } else {
                static_assert(_AlwaysFalse<MCLKFreqHz>);
            }
            
            // DCOCLKDIV = 16MHz
            CSCTL2 = FLLD_0 | ((MCLKFreqHz/XT1FreqHz)-1);
            
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
