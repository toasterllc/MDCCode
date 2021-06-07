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
    
    uint16_t i = 0;
    for (;;) {
        const bool connectOK = _msp.connect();
        mspprintf("Connect: %d\r\n", connectOK);
        __delay_cycles(8000000);
        if (!connectOK) continue;
        
        constexpr uint32_t AddrStart = 0xE300;
        constexpr uint32_t AddrEnd = 0xFF80;
        constexpr uint32_t Len = (AddrEnd-AddrStart)/2;
        
        mspprintf("Writing...\r\n");
        _msp.resetCRC();
        _msp.write(AddrStart, (uint16_t*)(0xC000), Len);
        
        mspprintf("Checking CRC...\r\n");
        const bool crcOK = _msp.verifyCRC(AddrStart, (AddrEnd-AddrStart)/2);
        mspprintf("crcOK = %d\r\n", crcOK);
        if (!crcOK) {
            for (;;);
        }
        
        
//        // Test writing/reading/CRC verify
//        {
////            const uint16_t data[4] = {0x1111, 0x2222, 0x3333, 0x4444};
////            const uint16_t data[4] = {0x3333, 0x4444, 0x5555, 0x6666};
////            const uint16_t data[4] = {0xAAAA, 0xBBBB, 0xCCCC, 0xDDDD};
////            const uint16_t data[4] = {0xFFFF, 0xEEEE, 0xDDDD, 0xCCCC};
//            uint16_t data[4] = {};
//            for (uint16_t& d : data) {
//                d = i;
//                if (i == 0xFFFF) i = 0x0000;
//                else i += 0x1111;
//            }
//            
//            mspprintf("Write: ");
//            for (const uint16_t& d : data) {
//                mspprintf("%x ", d);
//            }
//            mspprintf("\r\n");
//            _msp.write(AddrStart, data, std::size(data));
////            _msp.write(AddrStart+0, data+0, 1);
////            _msp.write(AddrStart+2, data+1, 1);
////            _msp.write(AddrStart+4, data+2, 1);
////            _msp.write(AddrStart+6, data+3, 1);
//        }
//        
//        {
//            uint16_t data[4] = {};
//            _msp.read(AddrStart, data, std::size(data));
//            mspprintf("Read: ");
//            for (uint16_t& d : data) {
//                mspprintf("%x ", d);
//            }
//            mspprintf("\r\n");
//        }
        
        
        
        
//        uint16_t data[8];
//        uint16_t x = 0;
//        for (uint32_t addr=AddrStart; addr<AddrEnd; addr+=sizeof(data)) {
//            for (uint16_t& d : data) {
//                d = i;
//                i++;
//            }
//            _msp.write(addr, data, std::size(data));
//        }
//        mspprintf("Done\r\n");
        
//        mspprintf("Checking CRC...\r\n");
//        const bool crcOK = _msp.verifyCRC(AddrStart, (AddrEnd-AddrStart)/2);
//        mspprintf("crcOK = %d\r\n", crcOK);
//        if (!crcOK) {
//            for (;;);
//        }
        
        
        
//        // Test writing/reading/CRC verify
//        for (int ii=0; ii<3; ii++)
//        {
//            uint16_t data[8];
//            uint16_t x = 0;
//            mspprintf("Writing: ");
//            for (uint16_t& d : data) {
//                d = i+x;
//                x++;
//                mspprintf("%x ", d);
//            }
//            mspprintf("\r\n");
//            
//            _msp.resetCRC();
//            _msp.write(AddrStart, data, std::size(data));
//            const bool crcOK = _msp.verifyCRC(AddrStart, std::size(data));
//            mspprintf("crcOK = %d\r\n", crcOK);
//            if (!crcOK) {
//                for (;;);
//            }
//            i++;
//        }
        
        _msp.disconnect();
        mspprintf("Disconnect\r\n");
        __delay_cycles(8000000);
    }
    
    return 0;
}
