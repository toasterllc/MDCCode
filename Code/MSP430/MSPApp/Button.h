#pragma once
#include <msp430.h>
#include "GPIO.h"

template<
typename T_Scheduler,
typename T_Pin
>
class T_Button {
private:
    using _AssertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Input, GPIO::Option::Interrupt10, GPIO::Option::Resistor1>;
    using _DeassertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Input, GPIO::Option::Interrupt01, GPIO::Option::Resistor1>;
    
public:
    using Pin = _AssertedInterrupt;
    
    enum class Event {
        Press,
        Hold,
    };
    
    // Reset(): start a new event-monitoring session
    //
    // Interrupts must be disabled (so that there's no race between us
    // calling Pin::Init() + resetting _Signal, and the ISR firing.)
    static void Reset() {
        // Wait for the button to be deasserted, in case it was already asserted when we entered this function
        {
            _DeassertedInterrupt::Init<_AssertedInterrupt>();
            _Signal = false;
            T_Scheduler::Wait([] { return _Signal; });
            // Debounce delay
            T_Scheduler::Sleep(_DebounceDelay);
        }
        
        // Configure ourself for the asserted transition
        _AssertedInterrupt::Init<_DeassertedInterrupt>();
        _Signal = false;
    }
    
    static bool EventPending() {
        return _Signal;
    }
    
    // EventRead(): determine whether a button press or hold occurred
    //
    // Interrupts must be disabled (so that there's no race between us
    // calling Pin::Init() + resetting _Signal, and the ISR firing.)
    static Event EventRead() {
        Assert(_Signal);
        
        // Debounce after asserted transition
        T_Scheduler::Sleep(_DebounceDelay);
        
        // Wait for 0->1 transition, or for the hold-timeout to elapse
        {
            _DeassertedInterrupt::Init<_AssertedInterrupt>();
            _Signal = false;
            const bool ok = T_Scheduler::Wait(_HoldDuration, [] { return _Signal; });
            // If we timed-out, then the button's being held
            if (!ok) return Event::Hold;
            // Otherwise, we didn't timeout, so the button was simply pressed
            return Event::Press;
        }
    }
    
    static void ISR() {
        _Signal = true;
    }
    
private:
    static constexpr auto _HoldDuration = T_Scheduler::template Ms<1500>;
    static constexpr auto _DebounceDelay = T_Scheduler::template Ms<2>;
    static inline volatile bool _Signal = false;
};
