#pragma once
#include <msp430.h>
#include "System.h"

template<
typename T_Pin
>
struct T_WiredMonitor {
    using _AssertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Interrupt01, GPIO::Option::Resistor0>;
    using _DeassertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Interrupt10, GPIO::Option::Resistor0>;
    
    using Pin = _AssertedInterrupt;
    
    static bool Wired() { return _Wired; }
    
    static void ISR(uint16_t iv) {
        const bool wired = (Pin::State::IES() == _AssertedInterrupt::IES());
        _Wired = wired;
        if (!wired) _AssertedInterrupt::template Init<_DeassertedInterrupt>();
        else        _DeassertedInterrupt::template Init<_AssertedInterrupt>();
    }
    
    static inline volatile bool _Wired = false;
};
