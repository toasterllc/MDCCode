#pragma once
#include <msp430.h>

template <uint32_t T_MCLKFreqHz, typename T_ClkPin, typename T_DataOutPin, typename T_DataInPin>
class T_SPI {
private:
    using _ClkManual = typename T_ClkPin::template Opts<GPIO::Option::Output1>;
    using _ClkPeriph = typename T_ClkPin::template Opts<GPIO::Option::Sel01>;
    using _DataOutDisabled = typename T_DataOutPin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor0>; // Pulldown to prevent floating input (particularly when ICE40 is off)
    using _DataOutEnabled = typename T_DataOutPin::template Opts<GPIO::Option::Sel01>;
    
public:
    struct Pin {
        using Clk       = _ClkManual;
        using DataOut   = _DataOutDisabled;
        using DataIn    = typename T_DataInPin::template Opts<GPIO::Option::Sel01>;
    };
    
    // ICEReset(): reset ICE comms by asserting `T_ClkPin` for some period
    static void ICEReset() {
        // Take over manual control of `T_ClkPin`
        _ClkManual::template Init<_ClkPeriph>();
        
        // Reset the ICE40 SPI state machine by asserting `T_ClkPin` for some period
        constexpr uint64_t ICE40SPIResetDurationUs = 18;
        _ClkManual::Write(1);
        // We're busy-waiting here because sleeping one Tick (512us) is way longer
        // than the time we need to wait (18us)
        __delay_cycles((((uint64_t)ICE40SPIResetDurationUs)*T_MCLKFreqHz) / 1000000);
        _ClkManual::Write(0);
        
        // Return control of `T_ClkPin` to the SPI peripheral (PA.6 = UCA0CLK)
        _ClkPeriph::template Init<_ClkManual>();
    }
    
    // Init(): configure SPI peripheral
    static void Init() {
        // Turn over control of `T_ClkPin` to the SPI peripheral (PA.6 = UCA0CLK)
        _ClkPeriph::template Init<_ClkManual>();
        
        // Assert USCI reset
        UCA0CTLW0 = UCSWRST;
        
        UCA0CTLW0 |=
            // phase=1, polarity=0, MSB first, width=8-bit
            UCCKPH | (UCCKPL&0) | UCMSB | (UC7BIT&0) |
            // mode=master, mode=3-pin SPI, mode=synchronous, clock=SMCLK
            UCMST | UCMODE_0 | UCSYNC | UCSSEL__SMCLK;
        
        // Our SPI clock needs to be slower because TXB0102 can't handle 16 MHz.
        // 1 MHz appears to be the fastest we can go. See:
        //   https://e2e.ti.com/support/logic-group/logic/f/logic-forum/1182055/txb0102-output-noise-prevents-high-speed-translation
        
        // fBitClock = fBRCLK / 16;
        UCA0BRW = 16;
        // No modulation
        UCA0MCTLW = 0;
        
        // De-assert USCI reset
        UCA0CTLW0 &= ~UCSWRST;
    }
    
    template <typename T_DataOut, typename T_DataIn>
    static void WriteRead(const T_DataOut& dataOut, T_DataIn* dataIn=nullptr) {
        // PA.4 = UCA0SIMO
        _DataOutEnabled::template Init<_DataOutDisabled>();
        
        const uint8_t* dataOutU8 = (const uint8_t*)&dataOut;
        for (size_t i=0; i<sizeof(dataOut); i++) {
            _TxRx(dataOutU8[i]);
        }
        
        // PA.4 = GPIO input
        _DataOutDisabled::template Init<_DataOutEnabled>();
        
        // 8-cycle turnaround
        _TxRx(0);
        
        // Clock in the response
        if (dataIn) {
            uint8_t* dataInU8 = (uint8_t*)dataIn;
            for (size_t i=0; i<sizeof(*dataIn); i++) {
                dataInU8[i] = _TxRx(0);
            }
        }
    }
    
private:
    static uint8_t _TxRx(uint8_t b) {
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
