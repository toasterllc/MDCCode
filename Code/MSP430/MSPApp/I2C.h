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
            (UCA10&0)   |   // 7bit own addr
            (UCSLA10&0) |   // 7bit slave addr
            (UCMM&0)    |   // single-master
            (UCMST&0)   |   // slave mode
            UCMODE_3    |   // i2c mode
            UCSYNC      |   // (not applicable)
            UCSSEL_0    |   // (not applicable in slave mode)
            (UCTXACK&0) |   // (not applicable during setup)
            (UCTR&0)    |   // receiver mode
            UCTXNACK    |   // (not applicable during setup)
            UCTXSTP     |   // (not applicable in slave mode)
            UCTXSTT     |   // (not applicable in slave mode)
            (UCSWRST&0) ;   // already set UCSWRST bit above
        
        UCB0I2COA0 = 
            (UCGCEN&0)  |   // don't respond to general calls
            UCOAEN      |   // enable this slave (slave 0)
            0x55        ;   // our slave address
        
        // Enable!
        UCB0CTLW0 &= ~UCSWRST;
    }
    
    static void Recv(T_Msg& msg) {
        uint8_t* b = reinterpret_cast<uint8_t*>(&msg);
        
        uint16_t ev = _WaitForEvent();
        // Confirm that we have a START condition
        Assert(ev == USCI_I2C_UCSTTIFG);
        
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
        
    }
    
    static void ISR() {
        // We should never be called until _Event is cleared
        Assert(!_Event);
        // Disable interrupts until current one is handled by our thread
        _I2CIntsSetEnabled(false);
        _Event = UCB0IV;
    }

private:
    static void _I2CIntsSetEnabled(bool en) {
        if (en) UCB0IE = UCSTTIE | UCSTPIE | UCTXIE0 | UCRXIE0;
        else    UCB0IE = 0;
    }
    
    static uint16_t _WaitForEvent() {
        _Event = std::nullopt;
        // Re-enable interrupts now that we're ready for an event
        _I2CIntsSetEnabled(true);
        T_Scheduler::Wait([&] { return _Event.has_value(); });
        return *_Event;
    }
    
    static inline std::optional<uint16_t> _Event;

#undef Assert
};
