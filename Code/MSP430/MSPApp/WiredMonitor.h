#pragma once
#include <msp430.h>
#include "System.h"

template<
typename T_Pin
>
struct T_WiredMonitor {
    using _Asserted = typename T_Pin::template Opts<GPIO::Option::Interrupt01, GPIO::Option::Resistor0>;
    using _Deasserted = typename T_Pin::template Opts<GPIO::Option::Interrupt10, GPIO::Option::Resistor0>;
    using _Disabled = typename T_Pin::template Opts<GPIO::Option::Input, GPIO::Option::Resistor0>;
    
    using Pin = _Disabled;
    
    static void Clear() {
        _Changed = false;
        if (!_Wired) _Asserted::template Init<_Deasserted, _Disabled>();
        else         _Deasserted::template Init<_Asserted>();
    }
    
    static bool Changed() {
        return _Changed;
    }
    
    static bool Wired() {
        return _Wired;
    }
    
    static void ISR(uint16_t iv) {
        _Changed = true;
        _Wired = !_Wired;
    }
    
    static inline volatile bool _Changed = false;
    static inline volatile bool _Wired = false;
};
