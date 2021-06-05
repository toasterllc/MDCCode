#include <msp430g2553.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include "MSP430Programmer.h"
#include "printf.h"

int putchar(int c) {
    while (!(UC0IFG & UCA0TXIFG));
    UCA0TXBUF = c;
    while (!(UC0IFG & UCA0TXIFG));
    return c;
}

// // Override write to route to UART.
// // We're assuming all writes are for printf...
// static void print(const char* str) {
//     while (*str) {
//         uint8_t b = *str;
//         if (b == '\n') txchar('\r');
//         txchar(b);
//         str++;
//     }
// }

static bool buttonAsserted() {
    // Active low
    return !(P1IN & BIT3);
}

int main() {
    // ## Stop watchdog timer
    {
        WDTCTL = WDTPW | WDTHOLD;
    }
    
    // ## Reset pin states
    {
        P1OUT   = 0x00;
        P1DIR   = 0xFF;
        P1SEL   = 0x00;
        P1SEL2  = 0x00;
        P1REN   = 0x00;
        
        P2OUT   = 0x00;
        P2DIR   = 0xFF;
        P2SEL   = 0x00;
        P2SEL2  = 0x00;
        P2REN   = 0x00;
    }
    
    // ## Set MCLK = 16MHz
    {
        DCOCTL = 0;
        BCSCTL1 = CALBC1_16MHZ;
        BCSCTL2 = 0;
        DCOCTL = CALDCO_16MHZ;
    }
    
    // ## Configure UART
    {
        // Assert UART reset
        UCA0CTL1 = UCSWRST;
        
            // Enable UART function for P1.1/UCA0RXD, P1.2/UCA0TXD
            P1DIR  &= ~(BIT1|BIT2);
            P1SEL  |=  (BIT1|BIT2);
            P1SEL2 |=  (BIT1|BIT2);
            
            // Configure UART for baud rate = 9600
            UCA0CTL0 = 0;
            UCA0CTL1 = UCSSEL1 | UCSWRST; // Use SMCLK for UART; keep UART in reset until we're finished configuring
            UCA0BR0 = 0x68;
            UCA0BR1 = 0;
            UCA0MCTL = (UCBRF1 | UCBRF0) | (UCOS16);
        
        // Release UART reset
        UCA0CTL1 &= ~UCSWRST;
    }
    
    // ## Configure P1.3 as an input with pull-up resistor
    // ## (Button S2 drives to ground when pressed.)
    {
        P1OUT   |=  BIT3;
        P1DIR   &= ~BIT3;
        P1SEL   &= ~BIT3;
        P1SEL2  &= ~BIT3;
        P1REN   |=  BIT3;
    }
    
    // // ## Configure P1.4 as an input with pull-down resistor
    // // ## (Motion sensor drives high when motion is detected.)
    // {
    //     P1OUT   &= ~BIT4;
    //     P1DIR   &= ~BIT4;
    //     P1SEL   &= ~BIT4;
    //     P1SEL2  &= ~BIT4;
    //     P1REN   |=  BIT4;
    // }
    
    // for (;;) {
    //     volatile uint16_t coreID = GetCoreID();
    //
    // }
    
    // for (int i=0;; i++) {
    //     // Wait while no input is asserted
    //     while (!buttonAsserted());
    //     printf("Hello %i\r\n", i);
    //     __delay_cycles(1600000); // Debounce
    //
    //     // Wait while any input is asserted
    //     while (buttonAsserted());
    //     __delay_cycles(1600000); // Debounce
    // }
    
    
    for (;;) {
        uint16_t coreID = GetCoreID();
        printf("CoreID %x\r\n", coreID);
        DelayMs(500);
    }
    
    
    return 0;
}
