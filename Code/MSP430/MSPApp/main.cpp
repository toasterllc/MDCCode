#include <msp430.h>

static void ledFlash() {
    for (;;) {
        PAOUT ^= BITE;
        __delay_cycles(100000);
    }
}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Cold start
    PAOUT   = BITE;
    PADIR   = BITE;
    PASEL0  = 0;
    PASEL1  = 0;
    PAREN   = BITC;
    PAIES   = 0;
    
    PM5CTL0 &= ~LOCKLPM5;
    
    PAIE    = BITC;
    
    if (SYSRSTIV == SYSRSTIV_LPM5WU) {
        ledFlash();
    }
    
    PAIFG   = 0;
    
    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
    PMMCTL0_L |= PMMREGOFF;
    
    // Go to sleep in LPM3.5
    __bis_SR_register(GIE | LPM3_bits);
    
    return 0;
}
