#pragma once
#include <msp430.h>
#include <atomic>
#include "Toastbox/Scheduler.h"
#include "GPIO.h"

template <
typename T_Scheduler,
typename T_PowerPin,
typename T_SignalPin,
[[noreturn]] void T_Error(uint16_t)
>
class T_Motion {
#define Assert(x) if (!(x)) T_Error(__LINE__)
private:
    using _PowerDisabled = typename T_PowerPin::template Opts<GPIO::Option::Output1>;
    using _PowerEnabled = typename T_PowerPin::template Opts<GPIO::Option::Output0>;
    
    // _SignalEnabled: motion sensor can only drive 1, so we have a pulldown
    using _SignalDisabled = typename T_SignalPin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor0>;
    using _SignalPowering = typename T_SignalPin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor1>;
    using _SignalEnabled = typename T_SignalPin::template Opts<GPIO::Option::Input, GPIO::Option::Interrupt01, GPIO::Option::Resistor0>;
    
public:
    struct Pin {
        using Power = _PowerDisabled;
        using Signal = _SignalDisabled;
    };
    
    static void Enabled(bool x) {
        _EnabledRequest = x;
    }
    
    static void WaitForMotion() {
        Toastbox::IntState ints(false);
        for (;;) {
            // Power on / off when requested
            if (_EnabledChanged()) {
                _Enable(_EnabledRequest.load());
            }
            
            // Wait for motion, or for a state-change request
            T_Scheduler::Wait([] { return _Signal.load() || _EnabledChanged(); });
            
            // If motion occurred, clear the signal and return
            if (_Signal.load()) {
                _Signal = false;
                return;
            }
        }
    }
    
    static bool _EnabledChanged() {
        return _Enabled != _EnabledRequest.load();
    }
    
    static void _Enable(bool en) {
        Assert(_Enabled != en);
        if (en) {
            // Turn on motion sensor power
            // We activate a pullup on the signal line (via _SignalPowering) to minimize
            // current draw on the signal line during this time. This is because the sensor's
            // output is indeterminite -- either Z or 1 -- during power-on. Since we don't
            // care about its value during power on, we don't want our pulldown draining
            // current in case the sensor is driving a 1.)
            _PowerEnabled::template Init<_PowerDisabled>();
            _SignalPowering::template Init<_SignalDisabled>();
            // Wait _PowerOnTimeMs for the sensor to turn on and stabilize
            T_Scheduler::Sleep(T_Scheduler::Ms(_PowerOnTimeMs));
            
            // Configure interrupt pin
            // We first switch to the '_SignalDisabled' configuration to switch back to a pulldown resistor,
            // and then simply enable interrupts.
            _SignalDisabled::template Init<_SignalPowering>();
            // Reset signal
            _Signal = false;
            // Enable interrupt
            _SignalEnabled::IESConfig();
        
        } else {
            // Turn off motion sensor power
            _PowerDisabled::template Init<_PowerEnabled>();
            _SignalDisabled::template Init<_SignalEnabled>();
        }
        
        _Enabled = en;
    }
    
    static void ISR() {
        _Signal = true;
    }
    
private:
    // _PowerOnTimeMs: time that it takes for the motion sensor to power on and stabilize
    static constexpr uint32_t _PowerOnTimeMs = 30000;
    static inline bool _Enabled = false;
    static inline std::atomic<bool> _EnabledRequest = false;
    static inline std::atomic<bool> _Signal = false;

#undef Assert
};
