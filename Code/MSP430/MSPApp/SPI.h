#pragma once
#include <msp430.h>

template <uint32_t MCLKFreqHz, typename ClkManual, typename UCA0CLK>
class SPIType {
public:
    static void Init() {
        // Reset the ICE40 SPI state machine by asserting ICE_MSP_SPI_CLK for some period
        {
            constexpr uint64_t ICE40SPIResetDurationUs = 18;
            ClkManual::Write(1);
            #warning don't busy wait
            __delay_cycles((((uint64_t)ICE40SPIResetDurationUs)*MCLKFreqHz) / 1000000);
            ClkManual::Write(0);
        }
        
        // Configure SPI peripheral
        {
            // Turn over control of ICE_MSP_SPI_CLK to the SPI peripheral (PA.6 = UCA0CLK)
            UCA0CLK::Init();
            
            // Assert USCI reset
            UCA0CTLW0 |= UCSWRST;
            
            UCA0CTLW0 |=
                // phase=1, polarity=0, MSB first, width=8-bit
                UCCKPH_1 | UCCKPL__LOW | UCMSB_1 | UC7BIT__8BIT |
                // mode=master, mode=3-pin SPI, mode=synchronous, clock=SMCLK
                UCMST__MASTER | UCMODE_0 | UCSYNC__SYNC | UCSSEL__SMCLK;
            
            // fBitClock = fBRCLK / 1;
            UCA0BRW = 0;
            // No modulation
            UCA0MCTLW = 0;
            
            // De-assert USCI reset
            UCA0CTLW0 &= ~UCSWRST;
        }
    }
    
    static uint8_t TxRx(uint8_t b) {
        #warning stop polling, use interrupts to wake ourself
        // Wait until `UCA0TXBUF` can accept more data
        while (!(UCA0IFG & UCTXIFG));
        // Clear UCRXIFG so we can tell when tx/rx is complete
        UCA0IFG &= ~UCRXIFG;
        // Start the SPI transaction
        UCA0TXBUF = b;
        // Wait for tx completion
        // Wait for UCRXIFG, not UCTXIFG! UCTXIFG signifies that UCA0TXBUF
        // can accept more data, not transfer completion. UCRXIFG signifies
        // rx completion, which implies tx completion.
        while (!(UCA0IFG & UCRXIFG));
        return UCA0RXBUF;
    }
};
