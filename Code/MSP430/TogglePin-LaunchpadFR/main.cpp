#include <msp430fr2433.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

int main() {
    // ## Stop watchdog timer
    {
        WDTCTL = WDTPW | WDTHOLD;
    }
    
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
    
    // ## Reset pin states
    {
        PAOUT   = 1<<14;
        PADIR   = 1<<14;
        PASEL0  = 0x0000;
        PASEL1  = 0x0000;
        PAREN   = 0x0000;
    }
    
    for (;;) {
        PAOUT ^= 1<<14;
        __delay_cycles(100000);
    }
    
    return 0;
}
