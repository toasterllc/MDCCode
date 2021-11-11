#include <msp430.h>

static void ledFlash() {
    for (;;) {
        P2OUT ^= BIT6;
        __delay_cycles(100000);
    }
}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Cold start
    P1OUT   = 0x00;
    P1DIR   = 0x00;
    P1SEL0  = 0x00;
    P1SEL1  = 0x00;
    P1REN   = 0x00;
    P1IES   = 0x00;
    
    P2OUT   = BIT6;
    P2DIR   = BIT6;
    P2SEL0  = 0x00;
    P2SEL1  = 0x00;
    P2REN   = BIT4;
    P2IES   = 0x00;
    
    PM5CTL0 &= ~LOCKLPM5;
    
    P1IE    = 0x00;
    P2IE    = BIT4;
    
    if (SYSRSTIV == SYSRSTIV_LPM5WU) {
        ledFlash();
    }
    
    P1IFG   = 0x00;
    P2IFG   = 0x00;
    
    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
    PMMCTL0_L |= PMMREGOFF;
    
    // Go to sleep in LPM3.5
    __bis_SR_register(GIE | LPM3_bits);
    
    return 0;
}
