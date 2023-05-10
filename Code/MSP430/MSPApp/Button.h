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
    
    // Init(): start a new event-monitoring session
    //
    // Ints: disabled
    //   Rationale: so that there's no race between us calling Pin::Init() + resetting _Pending,
    //   and the ISR firing.
    static void Init() {
        // Wait for the button to be deasserted, in case it was already asserted when we entered this function
        {
            _DeassertedInterrupt::template Init<_AssertedInterrupt>();
            _Pending = false;
            T_Scheduler::Wait([] { return _Pending; });
            // Debounce delay
            T_Scheduler::Sleep(_DebounceDelay);
        }
        
        // Configure ourself for the asserted transition
        _AssertedInterrupt::template Init<_DeassertedInterrupt>();
        _Pending = false;
    }
    
    static bool Pending() {
        return _Pending;
    }
    
    // Read(): determine whether a button press or hold occurred
    //
    // Ints: disabled
    //   Rationale: so that there's no race between us calling Pin::Init() + resetting _Pending,
    //   and the ISR firing.
    static Event Read() {
        Assert(_Pending);
        
        // Debounce after asserted transition
        T_Scheduler::Sleep(_DebounceDelay);
        
        // Wait for 0->1 transition, or for the hold-timeout to elapse
        {
            _DeassertedInterrupt::template Init<_AssertedInterrupt>();
            _Pending = false;
            const bool ok = T_Scheduler::Wait(_HoldDuration, [] { return _Pending; });
            // If we timed-out, then the button's being held
            if (!ok) return Event::Hold;
            // Otherwise, we didn't timeout, so the button was simply pressed
            return Event::Press;
        }
    }
    
    static void ISR() {
        _Pending = true;
    }
    
private:
    static constexpr auto _HoldDuration = T_Scheduler::template Ms<1400>;
    static constexpr auto _DebounceDelay = T_Scheduler::template Ms<2>;
    static inline volatile bool _Pending = false;
};
