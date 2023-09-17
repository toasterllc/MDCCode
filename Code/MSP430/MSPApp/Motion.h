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
    using _PowerOff = typename T_PowerPin::template Opts<GPIO::Option::Output1>;
    using _PowerOn = typename T_PowerPin::template Opts<GPIO::Option::Output0>;
    
    // Note that the motion sensor can only drive 1, so we have a pulldown in states
    // where we need to observe motion (or the power is off).
    using _SignalOff       = typename T_SignalPin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor0>;
    using _SignalOnIgnored = typename T_SignalPin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor1>;
    using _SignalOnPrepare = typename T_SignalPin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor0>;
    using _SignalOnEnabled = typename T_SignalPin::template Opts<GPIO::Option::Input, GPIO::Option::Interrupt01, GPIO::Option::Resistor0>;
    
public:
    struct Pin {
        using Power = _PowerOff;
        using Signal = _SignalOff;
    };
    
    // Power(): set power state of the motion sensor, and wait for it to turn on/off
    //
    // Ints: disabled (so that there's no race between us calling configuring our
    // pins + resetting _Signal, and the ISR firing.)
    static void Power(bool on) {
        if (on) {
            // Enable the motion signal's pullup first, which has the effect of turning on
            // the motion sensor very slowly.
            //
            // *** This is a nasty hack that slowly pre-charges the motion sensor via our pullup
            // *** resistor on the motion sensor's output (MOTION_SIGNAL).
            // *** If we turn on Q4 first, VDD_A_3V3 droops to ~2.2V and causes the MSP430 to
            // *** brownout.
            // *** To correct this, we need to add a physical resistor to Q4's gate to slow the
            // *** inrush current when turning on Q4.
            _SignalOnIgnored::template Init<_SignalOff>();
            T_Scheduler::Sleep(_PrePowerOnDelay);
            
            // Turn on motion sensor power
            // We activate a pullup on the signal line (via _SignalIgnored) to minimize
            // current draw on the signal line during this time. This is because the sensor's
            // output is indeterminite -- either Z or 1 -- during power-on. Since we don't
            // care about its value during power on, we don't want our pulldown draining
            // current in case the sensor is driving a 1.)
            _PowerOn::template Init<_PowerOff>();
            
            // Prepare interrupt pin
            // Switch to the _SignalOnPrepare config before switching to the _SignalOnEnabled
            // config. This is so we switch from a pullup resistor (via _SignalIgnored) to a
            // pulldown resistor (via _SignalOnPrepare), so that the signal line is low before
            // we enable interrupts, otherwise we'll get a spurious interrupt simply due to the
            // pullup resistor that we had previously.
            _SignalOnPrepare::template Init<_SignalOnIgnored>();
            
            // Enable interrupt
            _SignalOnEnabled::template Init<_SignalOnPrepare>();
            
            // Wait _PowerOnDelay for the sensor to turn on and stabilize
            T_Scheduler::Sleep(_PowerOnDelay);
        
        } else {
            // Turn off motion sensor power
            _PowerOff::template Init<_PowerOn>();
            _SignalOff::template Init<_SignalOnIgnored, _SignalOnPrepare, _SignalOnEnabled>();
        }
    }
    
    // Reset(): reset signal state to wait for motion
    //
    // Ints: disabled (so that there's no race between us calling configuring our
    // pins + resetting _Signal, and the ISR firing.)
    static void SignalReset() {
        // Reset signal
        _Signal = false;
    }
    
    static bool Signal() {
        return _Signal;
    }
    
//    // WaitForMotion(): wait for motion to occur
//    //
//    // Interrupts must be disabled (so that there's no race between us
//    // noticing _Signal==true and clearing _Signal.
//    static void WaitForMotion() {
//        // Reset signal
//        _Signal = false;
//        
//        // Prepare interrupt pin
//        // Switch to the _SignalOnPrepare config before switching to the _SignalOnEnabled
//        // config. This is so we switch from a pullup resistor (via _SignalIgnored) to a
//        // pulldown resistor (via _SignalOnPrepare), so that the signal line is low before
//        // we enable interrupts, otherwise we'll get a spurious interrupt simply due to the
//        // pullup resistor that we had previously.
//        _SignalOnPrepare::template Init<_SignalOnIgnored>();
//        
//        // Enable interrupt
//        #warning TODO: verify that we don't get a spurious interrupt here! we can verify simply by having a motion trigger enable at a partilcular time, and then verify that, in the absence of motion, no images are captured at that time.
//        #warning TODO: if we do get a spurious interrupt, add a delay above
//        _SignalOnEnabled::template Init<_SignalOnPrepare>();
//        
//        T_Scheduler::Wait([] { return _Signal; });
//        
//        // Return pin to the ignored state so our pulldown isn't wasting power until we need it again
//        _SignalOnIgnored::template Init<_SignalOff>();
//    }
    
    static void ISR() {
        _Signal = true;
        // Return pin to the ignored state so our pulldown isn't wasting power until we need it again
//        _SignalOnIgnored::template Init<_SignalOff>();
    }
    
    static constexpr uint32_t PowerOnDelayMs = 30000;
    
private:
    static constexpr uint32_t _PrePowerOnDelayMs = 100;
    static constexpr auto _PrePowerOnDelay = T_Scheduler::template Ms<_PrePowerOnDelayMs>;
    static constexpr auto _PowerOnDelay = T_Scheduler::template Ms<PowerOnDelayMs - _PrePowerOnDelayMs>;
    
    static inline volatile bool _Signal = false;
};
