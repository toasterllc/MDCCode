#pragma once
#include "assert.h"
#include "stm32f7xx.h"

class IRQState {
public:
    static void Enable() {
        __enable_irq();
    }
    
    static void Disable() {
        __disable_irq();
    }
    
    ~IRQState() {
        if (!_enabled) enable();
    }
    
    void enable() {
        assert(!_enabled);
        Enable();
        _enabled = true;
    }
    
    void disable() {
        assert(_enabled);
        Disable();
        _enabled = false;
    }

private:
    bool _enabled = true;
};
