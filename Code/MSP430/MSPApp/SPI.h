#pragma once
#include <msp430.h>

template <uint32_t T_MCLKFreqHz, typename T_ClkPin, typename T_DataOutPin, typename T_DataInPin, typename T_DataDirPin>
class SPIType {
public:
    struct Pin {
        using Clk       = typename T_ClkPin::template Opts<GPIO::Option::Output1>;
        using DataOut   = typename T_DataOutPin::template Opts<GPIO::Option::Input>;
        using DataIn    = typename T_DataInPin::template Opts<GPIO::Option::Sel01>;
        using DataDir   = typename T_DataDirPin::template Opts<GPIO::Option::Output0>;
    };
    
    static void Init() {
        // Reset the ICE40 SPI state machine by asserting ICE_MSP_SPI_CLK for some period
        {
            constexpr uint64_t ICE40SPIResetDurationUs = 18;
            _ClkManual::Write(1);
            #warning don't busy wait
            __delay_cycles((((uint64_t)ICE40SPIResetDurationUs)*T_MCLKFreqHz) / 1000000);
            _ClkManual::Write(0);
        }
        
        // Configure SPI peripheral
        {
            // Turn over control of ICE_MSP_SPI_CLK to the SPI peripheral (PA.6 = UCA0CLK)
            _ClkPeriph::Init();
            
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
    
    template <typename T_DataOut, typename T_DataIn>
    static void WriteRead(const T_DataOut& dataOut, T_DataIn* dataIn=nullptr) {
        static_assert(sizeof(size_t) == 2);
        
        // PA.4 level shifter direction = MSP->ICE
        Pin::DataDir::Write(1);
        
        // PA.4 = UCA0SIMO
        _DataOutEnabled::Init();
        
        const uint8_t* dataOutU8 = (const uint8_t*)&dataOut;
        for (size_t i=0; i<sizeof(dataOut); i++) {
            _TxRx(dataOutU8[i]);
        }
        
        // PA.4 = GPIO input
        _DataOutDisabled::Init();
        
        // PA.4 level shifter direction = MSP<-ICE
        Pin::DataDir::Write(0);
        
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
//    
//    void Read(void* data, size_t len) {
//        static_assert(sizeof(size_t) == 2);
//        
//        // PA.4 = UCA0SIMO
//        _DataOutEnabled::Init();
//        
//        // PA.4 level shifter direction = MSP->ICE
//        Pin::ICE_MSP_SPI_DATA_DIR::Write(1);
//        
//        SPI::TxRx(msg.type);
//        
//        for (uint8_t b : msg.payload) {
//            SPI::TxRx(b);
//        }
//    }
//    
//    void ICE::Transfer(const Msg& msg, Resp* resp) {
//        AssertArg((bool)resp == (bool)(msg.type & ICE::MsgType::Resp));
//        
//        // PA.4 = UCA0SIMO
//        Pin::ICE_MSP_SPI_DATA_UCA0SIMO::Init();
//        
//        // PA.4 level shifter direction = MSP->ICE
//        Pin::ICE_MSP_SPI_DATA_DIR::Write(1);
//        
//        SPI::TxRx(msg.type);
//        
//        for (uint8_t b : msg.payload) {
//            SPI::TxRx(b);
//        }
//        
//        // PA.4 = GPIO input
//        Pin::ICE_MSP_SPI_DATA_IN::Init();
//        
//        // PA.4 level shifter direction = MSP<-ICE
//        Pin::ICE_MSP_SPI_DATA_DIR::Write(0);
//        
//        // 8-cycle turnaround
//        SPI::TxRx(0);
//        
//        // Clock in the response
//        if (resp) {
//            for (uint8_t& b : resp->payload) {
//                b = SPI::TxRx(0);
//            }
//        }
//    }

private:
    using _ClkManual = typename Pin::Clk::template Opts<GPIO::Option::Output1>;
    using _ClkPeriph = typename Pin::Clk::template Opts<GPIO::Option::Sel01>;
    
    using _DataOutDisabled = typename Pin::DataOut::template Opts<GPIO::Option::Input>;
    using _DataOutEnabled = typename Pin::DataOut::template Opts<GPIO::Option::Sel01>;
    
    static uint8_t _TxRx(uint8_t b) {
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
