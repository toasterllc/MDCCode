#include <msp430fr2422.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

int main() {
    // ## Stop watchdog timer
    {
        // *0x01CC = 0x5a00 | 0x0080;
        WDTCTL = WDTPW | WDTHOLD;
    }
    
    // ## Reset pin states
    {
        PADIR   = 0x0004;   // *(PA_BASE+OFS_PADIR) = 0x04  =>  *0x0204 = 0x0004
        PAOUT   = 0x0004;   // *(PA_BASE+OFS_PAOUT) = 0x04  =>  *0x0202 = 0x0004
        
        // PAOUT   = 0x00;
        // PADIR   = 0x04;
        // PASEL0  = 0x00;
        // PASEL1  = 0x00;
        // PAREN   = 0x00;
        
        // P1OUT   = 0x00;
        // P1DIR   = 0xFF;
        // P1SEL   = 0x00;
        // P1SEL2  = 0x00;
        // P1REN   = 0x00;
        //
        // P2OUT   = 0x00;
        // P2DIR   = 0xFF;
        // P2SEL   = 0x00;
        // P2SEL2  = 0x00;
        // P2REN   = 0x00;
    }
    
    return 0;
}
