#pragma once
#include <msp430.h>

template <
typename T_Scheduler,
typename T_SCLPin,
typename T_SDAPin,
typename T_Msg,
uint8_t T_Addr,
[[noreturn]] void T_Error(uint16_t)
>
class I2CType {
#define Assert(x) if (!(x)) T_Error(__LINE__)

public:
    struct Pin {
        using SCL = typename T_SCLPin::template Opts<GPIO::Option::Sel01>;
        using SDA = typename T_SDAPin::template Opts<GPIO::Option::Sel01>;
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
            T_Addr          ;   // our slave address
        
        // Enable!
        UCB0CTLW0 &= ~UCSWRST;
    }
    
    static void Recv(T_Msg& msg) {
        _Event ev = _WaitForEvent();
        // Confirm that we have a START condition
        Assert(ev == _Event::Start);
        
        uint8_t* b = reinterpret_cast<uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvent();
            // Confirm that we received another byte
            Assert(ev == _Event::Rx);
            // Store the byte
            b[i] = UCB0RXBUF_L;
        }
        
        ev = _WaitForEvent();
        // Confirm that we have a STOP condition
        Assert(ev == _Event::Stop);
    }
    
    static void Send(const T_Msg& msg) {
        _Event ev = _WaitForEvent();
        // Confirm that we have a START condition
        Assert(ev == _Event::Start);
        
        const uint8_t* b = reinterpret_cast<const uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvent();
            // Confirm that we can write another byte
            Assert(ev == _Event::Tx);
            UCB0TXBUF_L = b[i];
        }
        
        // Wait for STOP condition
        for (;;) {
            ev = _WaitForEvent();
            switch (ev) {
            case _Event::Tx:
                // Send 0xFF after the end of our data
                UCB0TXBUF_L = 0xFF;
                continue;
            case _Event::Stop:
                return;
            default:
                // Unexpected event
                Assert(false);
            }
        }
    }
    
    static void ISR() {
        // We should never be called unless _Ev is cleared
        Assert(!_Ev);
        const _Event ev = (_Event)UCB0IV;
        // Ignore spurious interrupts
        if (!(uint16_t)ev) return;
        
        _Ev = ev;
        // Disable I2C interrupts until current event is handled by our thread
        _I2CIntsSetEnabled(false);
    }
    
private:
    enum class _Event : uint16_t {
        Start = USCI_I2C_UCSTTIFG,
        Stop  = USCI_I2C_UCSTPIFG,
        Rx    = USCI_I2C_UCRXIFG0,
        Tx    = USCI_I2C_UCTXIFG0,
    };
    
    static void _I2CIntsSetEnabled(bool en) {
        if (en) UCB0IE = UCSTTIE | UCSTPIE | UCTXIE0 | UCRXIE0;
        else    UCB0IE = 0;
    }
    
    static _Event _WaitForEvent() {
        _Ev = std::nullopt;
        // Re-enable I2C interrupts now that we're ready for an event
        _I2CIntsSetEnabled(true);
        T_Scheduler::Wait([&] { return _Ev.has_value(); });
        return *_Ev;
    }
    
    static inline std::optional<_Event> _Ev;

#undef Assert
};
