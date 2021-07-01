#include <msp430fr2422.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

int main() {
    // ## Stop watchdog timer
    {
        WDTCTL = WDTPW | WDTHOLD;
    }
    
    // ## Reset pin states
    {
        PAOUT   = 0x0000;
        PADIR   = 0x0000;
        PASEL0  = 0x0000;
        PASEL1  = 0x0000;
        PAREN   = 0x0000;
    }
    
    // Configure clock system
    {
        // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
        // This must happen before configuring the clock system.
        FRCTL0 = FRCTLPW | NWAITS_1;
        
        P2SEL1 |= BIT0 | BIT1; // Set XT1 pin as second function
        P2SEL0 &= ~(BIT0 | BIT1);
        do {
            CSCTL7 &= ~(XT1OFFG | DCOFFG); // Clear XT1 and DCO fault flag
            SFRIFG1 &= ~OFIFG;
        } while (SFRIFG1 & OFIFG); // Test oscillator fault flag
        
        __bis_SR_register(SCG0); // Disable FLL
        CSCTL3 |= SELREF__XT1CLK; // Set XT1 as FLL reference source
        CSCTL0 = 0; // Clear DCO and MOD registers
        CSCTL1 &= ~(DCORSEL_7); // Clear DCO frequency select bits first
        CSCTL1 |= DCORSEL_5; // Set DCO = 16MHz
        CSCTL2 = FLLD_0 + 487; // DCOCLKDIV = 16MHz
        __delay_cycles(3);
        __bic_SR_register(SCG0); // Enable FLL
        // Wait until FLL locks
        while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
        
        // set XT1 (~32768Hz) as ACLK source, ACLK = 32768Hz
        // default DCOCLKDIV as MCLK and SMCLK source
        CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
        
        P1DIR |= BIT0 | BIT1 | BIT2 | BIT3;     // set ACLK MCLK SMCLK and LED pin as output
        P1SEL1 |= BIT1 | BIT2 | BIT3;           // set ACLK MCLK and SMCLK pin as second function
    }
    
    // ## Unlock GPIOs
    {
        PM5CTL0 &= ~LOCKLPM5;
    }
    
    // // ## Set MCLK = 16MHz
    // {
    //     // Configure one FRAM waitstate as required by the device datasheet for MCLK
    //     // operation beyond 8MHz _before_ configuring the clock system.
    //     FRCTL0 = FRCTLPW | NWAITS_1; // Change the NACCESS_x value to add the right amount of waitstates
    //
    //     DCOCTL = 0;
    //     BCSCTL1 = CALBC1_16MHZ;
    //     BCSCTL2 = 0;
    //     DCOCTL = CALDCO_16MHZ;
    // }
    
    for (;;) {
        PAOUT ^= 1<<14;
        // __delay_cycles(100000);
    }
    
    return 0;
}
