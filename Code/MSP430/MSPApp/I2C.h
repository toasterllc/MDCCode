#pragma once
#include <msp430.h>

template <
typename T_Scheduler,
typename T_ClkPin,
typename T_DataPin,
typename T_Msg,
[[noreturn]] void T_Error(uint16_t)
>
class I2CType {
#define Assert(x) if (!(x)) T_Error(__LINE__)

public:
    struct Pin {
        using Clk       = typename T_ClkPin::template Opts<GPIO::Option::Sel01>;
        using Data      = typename T_DataPin::template Opts<GPIO::Option::Sel01>;
    };
    
    static void Init() {
        // Reset
        UCB0CTLW0 = UCSWRST;
        
        UCB0CTLW0 |=
            (UCA10&0)       |   // 7bit own addr
            (UCSLA10&0)     |   // 7bit slave addr
            (UCMM&0)        |   // single-master
            (UCMST&0)       |   // slave mode
            UCMODE_3        |   // i2c mode
            UCSYNC          |   // (not applicable)
            UCSSEL_0        |   // (not applicable in slave mode)
            (UCTXACK&0)     |   // (not applicable during setup)
            (UCTR&0)        |   // receiver mode
            (UCTXNACK&0)    |   // (not applicable during setup)
            (UCTXSTP&0)     |   // (not applicable in slave mode)
            (UCTXSTT&0)     |   // (not applicable in slave mode)
            (UCSWRST&0)     ;   // already set UCSWRST bit above
        
        UCB0CTLW1 = 
            (UCETXINT&0)    |   // UCTXIFGx is set after an address match
            UCCLTO_0        |   // disable clock low time-out counter
            (UCSTPNACK&0)   |   // (not applicable in slave mode)
            (UCSWACK&0)     |   // hardware controls address ACK
            UCASTP_0        |   // no automatic STOP generation
            UCGLIT_0        ;   // deglitch time = 50 ns
        
        UCB0I2COA0 = 
            (UCGCEN&0)      |   // don't respond to general calls
            UCOAEN          |   // enable this slave (slave 0)
            0x55            ;   // our slave address
        
        // Enable!
        UCB0CTLW0 &= ~UCSWRST;
    }
    
    static void Recv(T_Msg& msg) {
        uint16_t ev = _WaitForEvent();
        // Confirm that we have a START condition
        Assert(ev == USCI_I2C_UCSTTIFG);
        
        uint8_t* b = reinterpret_cast<uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvent();
            // Confirm that we received another byte
            Assert(ev == USCI_I2C_UCRXIFG0);
            // Store the byte
            b[i] = UCB0RXBUF_L;
        }
        
        ev = _WaitForEvent();
        // Confirm that we have a STOP condition
        Assert(ev == USCI_I2C_UCSTPIFG);
    }
    
    static void Send(const T_Msg& msg) {
        uint16_t ev = _WaitForEvent();
        // Confirm that we have a START condition
        Assert(ev == USCI_I2C_UCSTTIFG);
        
        const uint8_t* b = reinterpret_cast<const uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvent();
            // Confirm that we can write another byte
            Assert(ev == USCI_I2C_UCTXIFG0);
            UCB0TXBUF_L = b[i];
        }
        
        // Wait for STOP condition
        for (;;) {
            ev = _WaitForEvent();
            switch (ev) {
            // Request for more data: send 0xFF after the end of our data
            case USCI_I2C_UCTXIFG0:
                UCB0TXBUF_L = 0xFF;
                continue;
            // STOP condition
            case USCI_I2C_UCSTPIFG:
                return;
            // Unexpected event
            default:
                Assert(false);
            }
        }
    }
    
    static void ISR() {
        // We should never be called unless _Event is cleared
        Assert(!_Event);
        const uint16_t ev = UCB0IV;
        // Ignore spurious interrupts
        if (!ev) return;
        
        _Event = ev;
        // Disable I2C interrupts until current event is handled by our thread
        _I2CIntsSetEnabled(false);
    }

private:
    static void _I2CIntsSetEnabled(bool en) {
        if (en) UCB0IE = UCSTTIE | UCSTPIE | UCTXIE0 | UCRXIE0;
        else    UCB0IE = 0;
    }
    
    static uint16_t _WaitForEvent() {
        _Event = std::nullopt;
        // Re-enable I2C interrupts now that we're ready for an event
        _I2CIntsSetEnabled(true);
        T_Scheduler::Wait([&] { return _Event.has_value(); });
        return *_Event;
    }
    
    static inline std::optional<uint16_t> _Event;

#undef Assert
};
