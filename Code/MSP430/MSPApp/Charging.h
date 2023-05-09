#pragma once
#include <msp430.h>
#include "System.h"

template<
typename T_Pin
>
struct T_Charging {
    using _AssertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Interrupt01, GPIO::Option::Resistor0>;
    using _DeassertedInterrupt = typename T_Pin::template Opts<GPIO::Option::Interrupt10, GPIO::Option::Resistor0>;
    
    using Pin = _AssertedInterrupt;
    
    static bool Charging() {
        return _Charging;
    }
    
    static void ISR(uint16_t iv) {
        if (Pin::State::IES() == _AssertedInterrupt::IES()) {
            _Charging = true;
            _DeassertedInterrupt::template Init<_AssertedInterrupt>();
        } else {
            _Charging = false;
            _AssertedInterrupt::template Init<_DeassertedInterrupt>();
        }
    }
    
    static volatile inline bool _Charging = false;
};
