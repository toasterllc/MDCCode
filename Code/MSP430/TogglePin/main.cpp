#include <msp430fr2422.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

int main() {
    
    // Stop watchdog timer
    {
        WDTCTL = WDTPW | WDTHOLD;
    }
    
    // Reset pin states
    {
        PAOUT   = 0x0000;
        PADIR   = 0x0000;
        PASEL0  = 0x0000;
        PASEL1  = 0x0000;
        PAREN   = 0x0000;
    }
    
    // Configure clock system
    {
        constexpr uint32_t MCLKFreqHz = 16000000;
        constexpr uint32_t XT1FreqHz = 32768;
        
        // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
        // This must happen before configuring the clock system.
        FRCTL0 = FRCTLPW | NWAITS_1;
        
        // Make PA.8 and PA.9 XOUT/XIN
        PASEL1 |=  (BIT8 | BIT9);
        PASEL0 &= ~(BIT8 | BIT9);
        
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
            // Set DCO = 16MHz
            CSCTL1 |= DCORSEL_5;
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
    
    // Unlock GPIOs
    {
        PM5CTL0 &= ~LOCKLPM5;
    }
    
    // // Make PA.1 output ACLK
    // {
    //     PADIR  |=  (BIT1);
    //     PASEL1 |=  (BIT1);
    //     PASEL0 &= ~(BIT1);
    // }
    
    // // Make PA.3 output MCLK
    // {
    //     PADIR  |=  (BIT3);
    //     PASEL1 |=  (BIT3);
    //     PASEL0 &= ~(BIT3);
    // }
    
    for (;;);
    
    // for (;;) {
    //     PAOUT ^= 1<<14;
    //     // __delay_cycles(100000);
    // }
    
    return 0;
}
