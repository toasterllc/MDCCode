#pragma once
#include <msp430.h>

template <uint32_t XT1FreqHz, uint32_t MCLKFreqHz>
class ClockType {
public:
    static void Init() {
        // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
        // This must happen before configuring the clock system.
        #warning should we do this in 2 stages?
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
            
//            // Set DCO = 16MHz
//            CSCTL1 |= DCORSEL_5;
            
            // Set DCO = 1MHz
            CSCTL1 |= DCORSEL_0;
            
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
};
