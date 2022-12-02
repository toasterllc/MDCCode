#pragma once
#include <msp430.h>

template <uint32_t T_MCLKFreqHz, typename T_ClkPin, typename T_DataOutPin, typename T_DataInPin>
class SPIType {
public:
    struct Pin {
        using Clk       = typename T_ClkPin::template Opts<GPIO::Option::Output1>;
        using DataOut   = typename T_DataOutPin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor0>; // Pulldown to prevent floating input (particularly when ICE40 is off)
        using DataIn    = typename T_DataInPin::template Opts<GPIO::Option::Sel10>;
    };
    
    // ICEReset(): reset ICE comms by asserting `T_ClkPin` for some period
    static void ICEReset() {
        // Take over manual control of `T_ClkPin`
        _ClkManual::Init();
        
        // Reset the ICE40 SPI state machine by asserting `T_ClkPin` for some period
        constexpr uint64_t ICE40SPIResetDurationUs = 18;
        _ClkManual::Write(1);
        // We're busy-waiting here because sleeping one Tick (512us) is way longer
        // than the time we need to wait (18us)
        __delay_cycles((((uint64_t)ICE40SPIResetDurationUs)*T_MCLKFreqHz) / 1000000);
        _ClkManual::Write(0);
        
        // Return control of `T_ClkPin` to the SPI peripheral (PA.C = UCB0CLK)
        _ClkPeriph::Init();
    }
    
    // Init(): configure SPI peripheral
    static void Init() {
        // Turn over control of `T_ClkPin` to the SPI peripheral (PA.C = UCB0CLK)
        _ClkPeriph::Init();
        
        // Assert USCI reset
        UCB0CTLW0 = UCSWRST;
        
//        UCB0CTLW0 |=
//            // phase=1, polarity=0, MSB first, width=8-bit
//            UCCKPH_1 | UCCKPL__LOW | UCMSB_1 | UC7BIT__8BIT |
//            // mode=master, mode=3-pin SPI, mode=synchronous, clock=SMCLK
//            UCMST__MASTER | UCMODE_0 | UCSYNC__SYNC | UCSSEL__SMCLK;
        
        
        UCB0CTLW0 |=
            // phase=1, polarity=0, MSB first, width=8-bit
            UCCKPH | (UCCKPL&0) | UCMSB | (UC7BIT&0) |
            // mode=master, mode=3-pin SPI, mode=synchronous, clock=SMCLK
            UCMST | UCMODE_0 | UCSYNC | UCSSEL__SMCLK;
        
        // fBitClock = fBRCLK / 1;
        UCB0BRW = 0;
        
        // De-assert USCI reset
        UCB0CTLW0 &= ~UCSWRST;
    }
    
    template <typename T_DataOut, typename T_DataIn>
    static void WriteRead(const T_DataOut& dataOut, T_DataIn* dataIn=nullptr) {
        // PA.4 = UCB0SIMO
        _DataOutEnabled::Init();
        
        const uint8_t* dataOutU8 = (const uint8_t*)&dataOut;
        for (size_t i=0; i<sizeof(dataOut); i++) {
            _TxRx(dataOutU8[i]);
        }
        
        // PA.4 = GPIO input
        _DataOutDisabled::Init();
        
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
    using _ClkManual = typename Pin::Clk::template Opts<GPIO::Option::Output1>;
    using _ClkPeriph = typename Pin::Clk::template Opts<GPIO::Option::Sel10>;
    
    using _DataOutDisabled = typename Pin::DataOut;
    using _DataOutEnabled = typename Pin::DataOut::template Opts<GPIO::Option::Sel10>;
    
    static uint8_t _TxRx(uint8_t b) {
        // Wait until `UCB0TXBUF` can accept more data
        while (!(UCB0IFG & UCTXIFG));
        // Clear UCRXIFG so we can tell when tx/rx is complete
        UCB0IFG &= ~UCRXIFG;
        // Start the SPI transaction
        UCB0TXBUF = b;
        // Wait for tx completion
        // Wait for UCRXIFG, not UCTXIFG! UCTXIFG signifies that UCB0TXBUF
        // can accept more data, not transfer completion. UCRXIFG signifies
        // rx completion, which implies tx completion.
        while (!(UCB0IFG & UCRXIFG));
        return UCB0RXBUF;
    }
};
