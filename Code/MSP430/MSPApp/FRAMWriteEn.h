#pragma once
#include <msp430.h>
#include "Toastbox/IntState.h"

class FRAMWriteEn : Toastbox::IntState {
public:
    FRAMWriteEn() : IntState(false) {
        _prevSYSCFG0 = SYSCFG0 & 0x00FF; // Mask out the password field (FRWPPW)
        // Disable write protection
        // Assume FRWPOA=0 for now
        SYSCFG0 = FRWPPW | DFWP_0;
    }
    
    ~FRAMWriteEn() {
        SYSCFG0 = FRWPPW | _prevSYSCFG0;
    }
    
    // Copy/move: illegal
    FRAMWriteEn(const FRAMWriteEn& x)   = delete;
    FRAMWriteEn(FRAMWriteEn&& x)        = delete;
    
private:
    uint16_t _prevSYSCFG0 = 0;
};
