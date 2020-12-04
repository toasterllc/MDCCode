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
    
    static void Enable() {
        __enable_irq();
    }
    
    static void Restore(bool en) {
        if (en) Enable();
    }
    
    
//    static bool Set(bool en) {
//        
//        __disable_irq();
//        return
//    }
    
    
////    static bool Disable() {
////        
////        __disable_irq();
////        return
////    }
//    
//    static void Restore(bool en) {
//        if (en) __enable_irq();
//    }
    
    static void Sleep() {
        HAL_SuspendTick();
        __WFI();
        HAL_ResumeTick();
    }
    
    ~IRQState() {
        if (!_enabled) enable();
    }
    
    void enable() {
        Assert(!_enabled);
        Enable();
        _enabled = true;
    }
    
    void disable() {
        Assert(_enabled);
        Disable();
        _enabled = false;
    }

private:
    bool _enabled = true;
};
