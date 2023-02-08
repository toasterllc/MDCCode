#pragma once
#include <msp430.h>
#include <atomic>
#include "GPIO.h"

template <
typename T_Scheduler,
typename T_Pin,
uint16_t T_HoldDurationMs
>
class ButtonType {
private:
    using _AssertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Input, GPIO::Option::Interrupt10, GPIO::Option::Resistor1>;
    using _DeassertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Input, GPIO::Option::Interrupt01, GPIO::Option::Resistor1>;
    
public:
    using Pin = _AssertedInterrupt;
    
    enum class Event {
        Press,
        Hold,
    };
    
    static Event WaitForEvent() {
        constexpr uint16_t DebounceDelayMs = 2;
        
        Toastbox::IntState ints(false);
        
        // Wait for the button to be deasserted, in case it was already asserted when we entered this function
        {
            _DeassertedInterrupt::IESConfig();
            _Signal = false;
            T_Scheduler::Wait([] { return _Signal.load(); });
            // Debounce delay
            T_Scheduler::Sleep(T_Scheduler::Ms(DebounceDelayMs));
        }
        
        // Wait for 1->0 transition
        {
            _AssertedInterrupt::IESConfig();
            _Signal = false;
            T_Scheduler::Wait([] { return _Signal.load(); });
            // Debounce delay
            T_Scheduler::Sleep(T_Scheduler::Ms(DebounceDelayMs));
        }
        
        // Wait for 0->1 transition, or for the hold-timeout to elapse
        {
            _DeassertedInterrupt::IESConfig();
            _Signal = false;
            const bool ok = T_Scheduler::Wait(T_Scheduler::Ms(T_HoldDurationMs), [] { return _Signal.load(); });
            // If we timed-out, then the button's being held
            if (!ok) return Event::Hold;
            // Otherwise, we didn't timeout, so the button was simply pressed
            return Event::Press;
        }
    }
    
    static void OffConfig() {
        // Wait while button is asserted without running other tasks
        while (!Pin::Read()) T_Scheduler::Delay(T_Scheduler::Ms(10));
        // Debounce so we don't turn back on due to the bouncing signal
        T_Scheduler::Delay(T_Scheduler::Ms(10));
        // Configure interrupt for the device off state
        _AssertedInterrupt::IESConfig();
    }
    
    static void ISR() {
        _Signal = true;
    }
    
private:
    static inline std::atomic<bool> _Signal = false;
};
