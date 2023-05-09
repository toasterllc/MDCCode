#pragma once
#include <msp430.h>
#include "Toastbox/Scheduler.h"
#include "GPIO.h"
#include "Assert.h"

template<
typename T_Scheduler,
typename T_PowerPin,
typename T_SignalPin
>
class T_Motion {
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
    
    // Init(): turn on motion sensor and wait for it to initialize
    //
    // Interrupts must be disabled (so that there's no race between us
    // calling configuring our pins + resetting _Signal, and the ISR firing.)
    static void Init() {
        // Turn on motion sensor power
        // We activate a pullup on the signal line (via _SignalPowering) to minimize
        // current draw on the signal line during this time. This is because the sensor's
        // output is indeterminite -- either Z or 1 -- during power-on. Since we don't
        // care about its value during power on, we don't want our pulldown draining
        // current in case the sensor is driving a 1.)
        _PowerEnabled::template Init<_PowerDisabled>();
        _SignalPowering::template Init<_SignalDisabled>();
        // Wait _PowerOnTimeMs for the sensor to turn on and stabilize
        T_Scheduler::Sleep(_PowerOnDelay);
        
        // Configure interrupt pin
        // Switch to the _SignalDisabled configuration before switching to the _SignalEnabled
        // configuration. This is so we switch back from a pullup resistor (via _SignalPowering)
        // to a pulldown resistor (via _SignalDisabled), so that the signal line is low before
        // we enable interrupts, otherwise we'll get a spurious interrupt simply due to the
        // pullup resistor that we had previously.
        _SignalDisabled::template Init<_SignalPowering>();
        // Reset signal
        _Signal = false;
        // Enable interrupt
        _SignalEnabled::template Init<_SignalPowering>();
    }
    
    static void Reset() {
        // Turn off motion sensor power
        _PowerDisabled::template Init<_PowerEnabled>();
        _SignalDisabled::template Init<_SignalEnabled>();
    }
    
    // WaitForMotion(): wait for motion to occur
    static void WaitForMotion() {
        T_Scheduler::Wait([] { return _Signal; });
        _Signal = false;
    }
    
    static void ISR() {
        _Signal = true;
    }
    
private:
    // _PowerOnDelay: time that it takes for the motion sensor to power on and stabilize
    static constexpr auto _PowerOnDelay = T_Scheduler::template Ms<30000>;
    static inline volatile bool _Signal = false;
};
