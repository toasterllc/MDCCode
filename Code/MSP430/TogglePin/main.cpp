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
    
    // Unlock GPIOs
    {
        PM5CTL0 &= ~LOCKLPM5;
    }
    
    // Make PA.E an output
    {
        PADIR |= BITE;
    }
    
    // Toggle PA.E
    for (;;) {
        PAOUT ^= BITE;
        __delay_cycles(100000);
    }
    
    return 0;
}
