#pragma once
#include <msp430.h>
#include <atomic>

template <
typename T_Scheduler,
typename T_BatChrgLvlPin,
typename T_BatChrgLvlEnPin
>
class BatteryType {
#define Assert(x) if (!(x)) T_Error(__LINE__)
    
public:
    struct Pin {
        using BatChrgLvlPin = typename T_BatChrgLvlPin::template Opts<GPIO::Option::Input>;
        using BatChrgLvlEnPin = typename T_BatChrgLvlEnPin::template Opts<GPIO::Option::Output0>;
    };
    
#undef Assert
};
