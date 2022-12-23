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
        _ActiveIntsConfig(1);
        
        // Wait until we're active
        T_Scheduler::Wait([&] { return _Active.load(); });
        
        // Initialize I2C peripheral
        _I2CInit();
        
        // Observe 1->0 transitions on Pin::Active
        _ActiveIntsConfig(0);
    }
    
    template <typename T>
    static bool Recv(T& msg) {
        _Event ev = _WaitForEvent();
        if (ev == _Event::Inactive) return false;
        // Confirm that we have a START condition
        Assert(ev == _Event::Start);
        
        uint8_t* b = reinterpret_cast<uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvent();
            if (ev == _Event::Inactive) return false;
            // Confirm that we received another byte
            Assert(ev == _Event::Rx);
            // Store the byte
            b[i] = UCB0RXBUF_L;
        }
        
        ev = _WaitForEvent();
        if (ev == _Event::Inactive) return false;
        // Confirm that we have a STOP condition
        Assert(ev == _Event::Stop);
        return true;
    }
    
    template <typename T>
    static bool Send(const T& msg) {
        _Event ev = _WaitForEvent();
        if (ev == _Event::Inactive) return false;
        // Confirm that we have a START condition
        Assert(ev == _Event::Start);
        
        const uint8_t* b = reinterpret_cast<const uint8_t*>(&msg);
        for (size_t i=0; i<sizeof(msg); i++) {
            ev = _WaitForEvent();
            if (ev == _Event::Inactive) return false;
            // Confirm that we can write another byte
            Assert(ev == _Event::Tx);
            UCB0TXBUF_L = b[i];
        }
        
        // Wait for STOP condition
        for (;;) {
            ev = _WaitForEvent();
            if (ev == _Event::Inactive) return false;
            
            switch (ev) {
            case _Event::Tx:
                // Send 0xFF after the end of our data
                UCB0TXBUF_L = 0xFF;
                continue;
            case _Event::Stop:
                return true;
            default:
                // Unexpected event
                Assert(false);
            }
        }
    }
    
    static void ISR_I2C(uint16_t iv) {
        // We should never be called unless _IV is cleared
        Assert(!_IV);
        // Ignore spurious interrupts
        if (!iv) return;
        _IV = iv;
        // Disable I2C interrupts until _IV is handled by our thread
        _I2CIntsSetEnabled(false);
    }
    
    static void ISR_Active(uint16_t iv) {
        // Update _Active based on whether we're observing 0->1 or 1->0 transitions
        _Active = (Pin::Active::IES() == _ActiveInterrupt::IES());
    }
    
private:
    enum class _Event : uint16_t {
        None        = 0, // Must not conflict with possible interrupt IV values (stored in UCB0IV)
        Inactive    = 1, // Must not conflict with possible interrupt IV values (stored in UCB0IV)
        Start       = USCI_I2C_UCSTTIFG,
        Stop        = USCI_I2C_UCSTPIFG,
        Rx          = USCI_I2C_UCRXIFG0,
        Tx          = USCI_I2C_UCTXIFG0,
    };
    
    static void _I2CReset() {
        // Reset I2C peripheral
        UCB0CTLW0 = UCSWRST;
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
    
    static void _ActiveIntsConfig(bool dir) {
        // Disable interrupts while we change the interrupt config
        Toastbox::IntState ints(false);
        
        // Monitor for 0->1 transitions
        if (dir) {
            _ActiveInterrupt::template Init<_InactiveInterrupt>();
        
        // Monitor for 1->0 transitions
        } else {
            _InactiveInterrupt::template Init<_ActiveInterrupt>();
        }
        
        // After configuring the interrupt, ensure that the IFG reflects the state of the pin.
        // This is necessary because we may have missed a transition due to the inherent race
        // between changing the interrupt config and the pin changing state.
        Pin::Active::IFG(Pin::Active::Read() == dir);
    }
    
    static void _I2CIntsSetEnabled(bool en) {
        if (en) UCB0IE = UCSTTIE | UCSTPIE | UCTXIE0 | UCRXIE0;
        else    UCB0IE = 0;
    }
    
    static _Event _WaitForEvent() {
        _IV = 0;
        // Re-enable I2C interrupts now that we're ready for an event
        _I2CIntsSetEnabled(true);
        // Wait until we get an inactive interrupt, or an I2C event occurs
        T_Scheduler::Wait([&] { return !_Active.load() || _IV.load(); });
        if (!_Active.load()) return _Event::Inactive;
        return (_Event)_IV.load();
    }
    
    // Using std::atomic here because these fields are modified from the interrupt context
    static inline std::atomic<bool> _Active = false;
    static inline std::atomic<uint16_t> _IV = 0;
    
#undef Assert
};
