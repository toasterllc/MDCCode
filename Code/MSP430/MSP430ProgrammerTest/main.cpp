#include <msp430g2553.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <iterator>
#include "MSP430.h"
extern "C" {
#include "mspprintf.h"
}

extern "C" void mspputchar(int c) {
    while (!(UC0IFG & UCA0TXIFG));
    UCA0TXBUF = c;
    while (!(UC0IFG & UCA0TXIFG));
}

GPIO<4> _mspTest;
GPIO<5> _mspRst;
MSP430 _msp(_mspTest, _mspRst);

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
    
    __delay_cycles(20000000);
    
    for (;;) {
        __delay_cycles(8000000);
        
        mspprintf("Connecting\r\n");
        auto s = _msp.connect();
        mspprintf("-> %d\r\n", (uint8_t)s);
        if (s == _msp.Status::JTAGDisabled) {
            mspprintf("JTAG disabled; attempting erase...\r\n");
            s = _msp.erase();
            mspprintf("-> %d\r\n", (uint8_t)s);
            continue;
        }
        
        constexpr uint32_t AddrStart = 0xE300;
        constexpr uint32_t AddrEnd = 0xFF80;
        constexpr uint32_t Len = (AddrEnd-AddrStart)/2;
        
        mspprintf("Writing\r\n");
        _msp.resetCRC();
        _msp.write(AddrStart, (uint16_t*)(0xC000), Len);
        mspprintf("-> Done\r\n");
        
        mspprintf("Checking CRC\r\n");
        s = _msp.verifyCRC(AddrStart, (AddrEnd-AddrStart)/2);
        mspprintf("-> %d\r\n", (uint8_t)s);
        if (s != _msp.Status::OK) {
            for (;;);
        }
        
        _msp.disconnect();
        mspprintf("Disconnect\r\n");
        __delay_cycles(8000000);
    }
    
    return 0;
}
