#pragma once
#include "Assert.h"
#include "stm32f7xx.h"

class IRQState {
public:
    static void Enable() {
        __enable_irq();
    }
    
    static void Disable() {
        __disable_irq();
    }
    
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
