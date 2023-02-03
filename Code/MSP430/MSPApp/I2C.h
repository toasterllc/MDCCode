#pragma once
#include <msp430.h>
#include <atomic>

template <
typename T_Scheduler,
typename T_SCLPin,
typename T_SDAPin,
typename T_ActivePin,
uint8_t T_Addr,
[[noreturn]] void T_Error(uint16_t)
>
class I2CType {
#define Assert(x) if (!(x)) T_Error(__LINE__)

private:
    using _ActiveInterrupt = typename T_ActivePin::template Opts<GPIO::Option::Interrupt01, GPIO::Option::Resistor0>;
    using _InactiveInterrupt = typename T_ActivePin::template Opts<GPIO::Option::Interrupt10, GPIO::Option::Resistor0>;
    
public:
    struct Pin {
        using SCL = typename T_SCLPin::template Opts<GPIO::Option::Sel01>;
        using SDA = typename T_SDAPin::template Opts<GPIO::Option::Sel01>;
        using Active = _ActiveInterrupt;
    };
    
    static void WaitUntilActive() {
        // Keep I2C peripheral in reset until we get the active interrupt
        _I2CReset();
        
        // Observe 0->1 transitions on Pin::Active
        _ActiveInterrupt::IESConfig();
        
        // Wait until we're active
        _WaitForEvents(_EventActive);
        
        // Initialize I2C peripheral
        _I2CInit();
        
        // Observe 1->0 transitions on Pin::Active
        _InactiveInterrupt::IESConfig();
    }
    
    template <typename T>
    static bool Recv(T& msg) {
        _Events ev = _WaitForEvents(_EventStart | _EventInactive);
        if (ev & _EventInactive) return false;
        
        uint8_t* b = reinterpret_cast<uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvents(_EventRx | _EventStop | _EventInactive);
            if (ev & _EventInactive) return false;
            // Only allow STOP events on the very last byte
            Assert(!(ev & _EventStop) || (i == (sizeof(msg)-1)));
            // Confirm that we received another byte
            Assert(ev & _EventRx);
            // Store the byte
            b[i] = UCB0RXBUF_L;
        }
        
        // If our loop didn't receive a STOP event, wait for it now
        if (!(ev & _EventStop)) {
            ev = _WaitForEvents(_EventStop | _EventInactive);
            if (ev & _EventInactive) return false;
        }
        
        return true;
    }
    
    template <typename T>
    static bool Send(const T& msg) {
        _Events ev = _WaitForEvents(_EventStart | _EventInactive);
        if (ev & _EventInactive) return false;
        
        const uint8_t* b = reinterpret_cast<const uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvents(_EventTx | _EventStop | _EventInactive);
            if (ev & _EventInactive) return false;
            // Ensure that we haven't gotten a STOP before we're done responding
            Assert(!(ev & _EventStop));
            UCB0TXBUF_L = b[i];
        }
        
        ev = _WaitForEvents(_EventStop | _EventInactive);
        if (ev & _EventInactive) return false;
        return true;
    }
    
    static void ISR_I2C(uint16_t iv) {
        switch (__even_in_range(iv, USCI_I2C_UCTXIFG0)) {
        case USCI_I2C_UCSTTIFG: _Ev |= _EventStart; break;
        case USCI_I2C_UCSTPIFG: _Ev |= _EventStop;  break;
        case USCI_I2C_UCRXIFG0: _Ev |= _EventRx;    break;
        case USCI_I2C_UCTXIFG0: _Ev |= _EventTx;    break;
        default:                                    break;
        }
    }
    
    static void ISR_Active(uint16_t iv) {
        const bool active = (Pin::Active::IES() == _ActiveInterrupt::InitCfg::IES());
        _Ev |= (active ? _EventActive : _EventInactive);
    }
    
private:
    using _Events = uint16_t;
    static constexpr _Events _EventNone       = 0;
    static constexpr _Events _EventActive     = 1<<0;
    static constexpr _Events _EventInactive   = 1<<1;
    static constexpr _Events _EventStart      = 1<<2;
    static constexpr _Events _EventStop       = 1<<3;
    static constexpr _Events _EventRx         = 1<<4;
    static constexpr _Events _EventTx         = 1<<5;
    
    static void _I2CReset() {
        // Reset I2C peripheral
        // This automatically resets our interrupt configuruation (UCB0IFG UCB0IE)
        UCB0CTLW0 = UCSWRST;
        // Clear our events (making sure to do this after we reset the I2C peripheral to ensure it stays cleared)
        _Ev = _EventNone;
    }
    
    static void _I2CInit() {
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
            (UCSWRST&0)     ;   // already set UCSWRST bit in _I2CReset()
        
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
        
        // Enable!
        UCB0CTLW0 &= ~UCSWRST;
        
        // Enable interrupts
        // User's guide says to enable interrupts after clearing UCSWRST
        UCB0IE = UCSTTIE | UCSTPIE | UCTXIE0 | UCRXIE0;
    }
    
    static _Events _WaitForEvents(_Events events) {
        Toastbox::IntState ints(false);
        T_Scheduler::Wait(events, [] (_Events events) { return (bool)(_Ev & events); });
        
        const _Events ev = _Ev & events;
        // Clear the events that we're returning
        _Ev &= ~ev;
        return ev;
    }
    
    static inline _Events _Ev = _EventNone;
    
#undef Assert
};
