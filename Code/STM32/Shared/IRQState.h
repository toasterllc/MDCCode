#pragma once
#include "Assert.h"
#include "stm32f7xx.h"

class IRQState {
public:
    
    static bool Disable() {
        // __get_PRIMASK() returns whether interrupts were masked, while
        // we return whether interrupts were enabled.
        bool en = !__get_PRIMASK();
        __disable_irq();
        return en;
    }
    
    static void Restore(bool en) {
        if (en) __enable_irq();
    }
    
//    static void Enable() {
//        __enable_irq();
//    }
    
    static void Sleep() {
        HAL_SuspendTick();
        __WFI();
        HAL_ResumeTick();
    }
    
    ~IRQState() {
        restore();
    }
    
    void disable() {
        _oldEnabled = Disable();
    }
    
    void restore() {
        Restore(_oldEnabled);
        _oldEnabled = false;
    }
    
private:
    bool _oldEnabled = false;
};
