#include <msp430fr2433.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

__attribute__((interrupt(PORT2_VECTOR)))
void _isr_port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV_P2IFG3)) {
    case P2IV_P2IFG3:
        PAOUT ^= 1<<0;
        break;
    
    default:
        break;
    }
}

int main() {
    WDTCTL = WDTPW | WDTHOLD;
    
    PM5CTL0 &= ~LOCKLPM5;
    
    PAOUT   = 0x0801;
    PADIR   = 0x0001;
    PASEL0  = 0x0000;
    PASEL1  = 0x0000;
    PAREN   = 0x0800;
    PAIE    = 0x0800;
    PAIES   = 0x0000;
    
    // __bis_SR_register(GIE);
    // for (;;);
    //
    // for (;;) {
    //     __delay_cycles(1000000);
    //     __bis_SR_register(GIE);
    //     __bic_SR_register(GIE);
    // }
    
    // Enable interrupts + go to sleep
    __bis_SR_register(GIE | LPM1_bits);
    
    return 0;
}
