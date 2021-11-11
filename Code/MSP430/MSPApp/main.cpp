#include <msp430.h>

static void ledFlash() {
    for (;;) {
        P2OUT ^= BIT6;
        __delay_cycles(100000);
    }
}

static void delay(int sec) {
    for (int i=0; i<sec; i++) {
        __delay_cycles(1000000);
    }
}

__attribute__((interrupt(PORT2_VECTOR)))
void _isr() {
    // Wake from LPM3.5
    ledFlash();
    
//    switch(__even_in_range(P2IV, P2IV_P2IFG3)) {
//    case P2IV_P2IFG3:
//        P1OUT ^= 0x01;
//        break;
//    default:
//        break;
//    }
}

static void _sleep() {
    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
    PMMCTL0_L |= PMMREGOFF;
    
    // Go to sleep in LPM3.5
    __bis_SR_register(GIE | LPM3_bits);
}

//__attribute__((section(".data"), noinline)) // Trailing semicolon is a hack to silence an assembler warning
//void _sleep() {
//    // Disable regulator so we enter LPM3.5 (instead of just LPM3)
//    PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
//    PMMCTL0_L |= PMMREGOFF;
//    
////    FRCTL0 = FRCTLPW;
////    GCCTL0 &= ~(FRPWR|FRLPMPWR);
////    FRCTL0_H = 0;
//    // Go to sleep in LPM3.5
//    __bis_SR_register(GIE | LPM3_bits);
//}

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
    P2REN   = BIT5;
    P2IES   = 0x00;
    
    PM5CTL0 &= ~LOCKLPM5;
    
    P1IE    = 0x00;
    P2IE    = BIT5;
    
    if (SYSRSTIV == SYSRSTIV_LPM5WU) {
        ledFlash();
        __bis_SR_register(GIE);
        for (;;);
//        // Wake from LPM3.5
//        P1DIR = 0x01;
//        for (;;) {
//            P1OUT ^= 0x01;
//            __delay_cycles(100000);
//        }
    }
    
    delay(7);
    
    P1IFG   = 0x00;
    P2IFG   = 0x00;
    
    _sleep();
    
    return 0;
}
