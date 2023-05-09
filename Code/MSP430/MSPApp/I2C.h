#pragma once
#include <msp430.h>
#include "System.h"

template<
typename T_Scheduler,
typename T_SCLPin,
typename T_SDAPin,
typename T_ActivePin,
uint8_t T_Addr
>
class T_I2C {
public:
    struct Pin {
        using SCL = typename T_SCLPin::template Opts<GPIO::Option::Sel01>;
        using SDA = typename T_SDAPin::template Opts<GPIO::Option::Sel01>;
    };
    
    // Init(): configure I2C peripheral and reset all state
    static void Init() {
        UCB0CTLW0 =
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
            UCSWRST         ;   // reset
        
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
            T_Addr          ;   // our slave address
        
        // Clear our events (making sure to do this after we reset the I2C peripheral to ensure it stays cleared)
        _Ev = _EventNone;
        
        // Enable!
        UCB0CTLW0 &= ~UCSWRST;
        
        // Enable interrupts
        // User's guide says to enable interrupts after clearing UCSWRST
        UCB0IE = UCSTTIE | UCSTPIE | UCTXIE0 | UCRXIE0;
    }
    
    // Abort(): causes the current or next Recv()/Send() to bail and return false.
    // This is intended to be called from the interrupt context when it's known that the master has gone away.
    static void Abort() {
        _Ev |= _EventAbort;
    }
    
    template<typename T>
    static bool Recv(T& msg) {
        _Events ev = _WaitForEvents(_EventStart | _EventAbort);
        if (ev & _EventAbort) return false;
        
        uint8_t* b = reinterpret_cast<uint8_t*>(&msg);
        size_t len = 0;
        for (;;) {
            ev = _WaitForEvents(_EventRx | _EventStop | _EventAbort);
            if (ev & _EventAbort) return false;
            if (ev & _EventRx) {
                // Check if we received too much data
                if (len >= sizeof(msg)) return false;
                // Store the byte
                b[len] = UCB0RXBUF_L;
                len++;
            }
            if (ev & _EventStop) break;
        }
        
        // Verify we got the correct number of bytes
        if (len != sizeof(msg)) return false;
        
        return true;
    }
    
    template<typename T>
    static bool Send(const T& msg) {
        _Events ev = _WaitForEvents(_EventStart | _EventAbort);
        if (ev & _EventAbort) return false;
        
        const uint8_t* b = reinterpret_cast<const uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvents(_EventTx | _EventStop | _EventAbort);
            if (ev & _EventAbort) return false;
            // Ensure that we haven't gotten a STOP before we're done responding
            if (ev & _EventStop) return false;
            UCB0TXBUF_L = b[i];
        }
        
        ev = _WaitForEvents(_EventStop | _EventAbort);
        if (ev & _EventAbort) return false;
        return true;
    }
    
    static void ISR_I2C(uint16_t iv) {
        switch (iv) {
        case USCI_I2C_UCSTTIFG: _Ev |= _EventStart; break;
        case USCI_I2C_UCSTPIFG: _Ev |= _EventStop;  break;
        case USCI_I2C_UCRXIFG0: _Ev |= _EventRx;    break;
        case USCI_I2C_UCTXIFG0: _Ev |= _EventTx;    break;
        default:                                    break;
        }
    }
    
private:
    using _Events = uint16_t;
    static constexpr _Events _EventNone       = 0;
    static constexpr _Events _EventAbort      = 1<<0;
    static constexpr _Events _EventStart      = 1<<1;
    static constexpr _Events _EventStop       = 1<<2;
    static constexpr _Events _EventRx         = 1<<3;
    static constexpr _Events _EventTx         = 1<<4;
    
    static _Events _WaitForEvents(_Events events) {
        Toastbox::IntState ints(false);
        
        static _Events Mask = 0;
        Mask = events;
        T_Scheduler::Wait([] { return (bool)(_Ev & Mask); });
        
        const _Events ev = _Ev & events;
        // Clear the events that we're returning
        _Ev &= ~ev;
        return ev;
    }
    
    static volatile inline _Events _Ev = _EventNone;
};
