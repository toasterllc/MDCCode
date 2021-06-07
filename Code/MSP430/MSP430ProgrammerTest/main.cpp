#include <msp430g2553.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include "MSP430.h"
#include "printf.h"

int putchar(int c) {
    while (!(UC0IFG & UCA0TXIFG));
    UCA0TXBUF = c;
    while (!(UC0IFG & UCA0TXIFG));
    return c;
}

static bool buttonAsserted() {
    // Active low
    return !(P1IN & BIT3);
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
    
    for (int i=0;; i++) {
        const bool r = _msp.connect();
        printf("Connect: %d\r\n", r);
        __delay_cycles(8000000);
        
        constexpr uint16_t DeviceIDAddr = 0x00001A04;
        constexpr uint16_t AddrStart = 0xE300;
        constexpr uint16_t AddrEnd = 0xFF7F;
        constexpr uint16_t Len = (AddrEnd-AddrStart+1)/2;
        
//        // Test writing / CRC
//        {
//            _msp.resetCRC();
//            const uint16_t val = 0x1234;
//            _msp.write(AddrStart, &val, 1);
//            _msp.verifyCRC(AddrStart, 1);
//        }
        
//        // Test reading
//        {
//            uint16_t val = 0;
//            _msp.read(AddrStart, &val, 1);
//            printf("val: %x\r\n", val);
//        }
        
        
        
        // Test writing/reading
        {
            uint16_t val = 0;
            _msp.read(AddrStart, &val, 1);
            printf("AAA *AddrStart=%x\r\n", val);
            
            _msp.read(DeviceIDAddr, &val, 1);
            printf("BBB *DeviceIDAddr=%x\r\n", val);
            
            val = i;
            _msp.write(AddrStart, &val, 1);
            printf("CCC WROTE %x\r\n", val);
            
            _msp.read(DeviceIDAddr, &val, 1);
            printf("EEE *DeviceIDAddr=%x\r\n", val);
            
            val = 0;
            _msp.read(AddrStart, &val, 1);
            printf("DDD *AddrStart=%x\r\n", val);
            
            _msp.read(DeviceIDAddr, &val, 1);
            printf("EEE *DeviceIDAddr=%x\r\n", val);
        }
        
//        uint16_t val = 0;
//        _msp.read(AddrStart, &val, 1);
//        printf("val: %x\r\n", val);
        
//        uint16_t val = 0;
//        _msp.read(AddrStart, &val, 1);
//        printf("val: %x\r\n", val);
//        
//        _msp.verifyCRC(AddrStart, 1);
//        
//        _msp.write(AddrStart, );
//        _msp.verifyCRC(AddrStart, 1);
        
        _msp.disconnect();
        printf("Disconnect\r\n");
        __delay_cycles(8000000);
    }
    
    return 0;
}
