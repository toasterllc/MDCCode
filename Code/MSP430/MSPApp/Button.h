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
            T_Scheduler::Wait([&] { return _Signal.load(); });
            // Debounce delay
            T_Scheduler::Sleep(T_Scheduler::Ms(DebounceDelayMs));
        }
        
        // Wait for 1->0 transition
        {
            _AssertedInterrupt::IESConfig();
            _Signal = false;
            T_Scheduler::Wait([&] { return _Signal.load(); });
            // Debounce delay
            T_Scheduler::Sleep(T_Scheduler::Ms(DebounceDelayMs));
        }
        
        // Wait for 0->1 transition, or for the hold-timeout to elapse
        {
            _DeassertedInterrupt::IESConfig();
            _Signal = false;
            auto ok = T_Scheduler::Wait(T_Scheduler::Ms(T_HoldDurationMs), [&] { return _Signal.load(); });
            // If we timed-out, then the button's being held
            if (!ok) return Event::Hold;
            // Otherwise, we didn't timeout, so the button was simply pressed
            return Event::Press;
        }
        
//        // Debounce
//        for (;;) {
//            _Signal = false;
//            auto ok = T_Scheduler::Wait(T_Scheduler::Ms(DebounceDurationMs), [&] { return _Signal; });
//            if (!ok) break;
//        }
//        
//        
//        for (;;) {
//            _Signal = false;
//            T_Scheduler::Wait([&] { return _Signal; });
//            // Debounce
//            auto ok = T_Scheduler::Wait(T_Scheduler::Ms(DebounceDurationMs), [&] { return _Signal; });
//            if (!ok) break;
//        }
//        
//        // Wait for 0->1 transition, or for the hold-timeout to elapse
//        _DeassertedInterrupt::IESConfig();
//        for (;;) {
//            _Signal = false;
//            auto ok = T_Scheduler::Wait(T_Scheduler::Ms(T_HoldDurationMs), [&] { return _Signal; });
//        }
//        
//        if (!ok) return Event::Hold;
//        return Event::Press;
    }
    
    static void ISR() {
        _Signal = true;
    }
    
private:
    static inline std::atomic<bool> _Signal = false;
};
