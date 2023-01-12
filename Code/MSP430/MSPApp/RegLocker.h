#pragma once
#include <msp430.h>

template <
auto& T_Reg,
uint16_t T_Unlock,
uint16_t T_Lock
>
class RegLocker {
public:
    RegLocker() {
        T_Reg = T_Unlock;
    }
    
    ~RegLocker() {
        T_Reg = T_Lock;
    }
    
    // Copy/move: illegal
    RegLocker(const RegLocker& x)   = delete;
    RegLocker(RegLocker&& x)        = delete;
};

using FRAMWriteEn   = RegLocker<SYSCFG0,    FRWPPW,     FRWPPW|DFWP|PFWP>;
using PMMUnlock     = RegLocker<PMMCTL0_H,  PMMPW_H,    0>;
