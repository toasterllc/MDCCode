#pragma once
#include "Assert.h"
#include "stm32f7xx.h"

class IRQState {
public:
    
    static bool Enabled() {
        // __get_PRIMASK() returns whether interrupts were masked, while
        // we return whether interrupts were enabled.
        return !__get_PRIMASK();
    }
    
    static bool Enable() {
        const bool en = Enabled();
        __enable_irq();
        return en;
    }
    
    static bool Disable() {
        const bool en = Enabled();
        __disable_irq();
        return en;
    }
    
    static void Restore(bool en) {
        if (en) __enable_irq();
        else __disable_irq();
    }
    
    static void Sleep() {
//        HAL_SuspendTick();
        __WFI();
//        HAL_ResumeTick();
    }
    
    ~IRQState() {
        restore();
    }
    
    void enable() {
        Assert(!_prevEnValid);
        _prevEn = Enable();
        _prevEnValid = true;
    }
    
    void disable() {
        Assert(!_prevEnValid);
        _prevEn = Disable();
        _prevEnValid = true;
    }
    
    void restore() {
        if (_prevEnValid) {
            Restore(_prevEn);
            _prevEnValid = false;
        }
    }
    
private:
    bool _prevEn = false;
    bool _prevEnValid = false;
};
