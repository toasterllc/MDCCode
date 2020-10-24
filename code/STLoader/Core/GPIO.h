#pragma once
#include "stm32f7xx.h"

class GPIO {
public:
    GPIO(GPIO_TypeDef* port, uint16_t pin) {
        _port = port;
        _pin = pin;
    }
    
    void init(uint32_t mode, uint32_t pull, uint32_t speed) {
        GPIO_InitTypeDef cfg = {
            .Pin = _pin,
            .Mode = mode,
            .Pull = pull,
            .Speed = speed,
            .Alternate = 0,
        };
        
        HAL_GPIO_Init(_port, &cfg);
    }
    
    bool read() {
        return HAL_GPIO_ReadPin(_port, _pin)==GPIO_PIN_SET;
    }
    
    void write(bool x) {
        HAL_GPIO_WritePin(_port, _pin, (x ? GPIO_PIN_SET : GPIO_PIN_RESET));
    }

private:
    GPIO_TypeDef* _port = nullptr;
    uint16_t _pin = 0;
};
