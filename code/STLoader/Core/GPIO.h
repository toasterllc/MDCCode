#pragma once
#include "stm32f7xx_hal.h"

template <GPIO_TypeDef* port, uint16_t pin>
class GPIO {
public:
    void config(uint32_t mode, uint32_t pull, uint32_t speed) {
        HAL_GPIO_WritePin(port, pin, GPIO_PIN_RESET);
        
        GPIO_InitTypeDef cfg = {
            .Pin = pin,
            .Mode = mode,
            .Pull = pull,
            .Speed = speed,
            .Alternate = 0,
        };
        
        HAL_GPIO_Init(port, &cfg);
    }
    
    bool read() {
        return HAL_GPIO_ReadPin(port, pin)==GPIO_PIN_SET;
    }
    
    void write(bool x) {
        HAL_GPIO_WritePin(port, pin, (x ? GPIO_PIN_SET : GPIO_PIN_RESET));
    }
}
