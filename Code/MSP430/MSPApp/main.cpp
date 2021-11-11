#include <msp430.h>

#define LED_BIT     BITE
#define INT_BIT     BITC

static void ledFlash() {
    for (;;) {
        PAOUT ^= LED_BIT;
        __delay_cycles(100000);
    }
}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Cold start
    PAOUT   = LED_BIT;
    PADIR   = LED_BIT;
    PASEL0  = 0;
    PASEL1  = 0;
    PAREN   = INT_BIT;
    PAIES   = 0;
    
    PM5CTL0 &= ~LOCKLPM5;
    
    PAIE    = INT_BIT;
    
    if (SYSRSTIV == SYSRSTIV_LPM5WU) {
        ledFlash();
    }
    
    PAIFG = 0;
    
    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
    PMMCTL0_L |= PMMREGOFF;
    
    // Go to sleep in LPM3.5
    __bis_SR_register(GIE | LPM3_bits);
    
    return 0;
}
