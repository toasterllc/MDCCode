#pragma once
#include "stm32f7xx.h"

extern "C" GPIO_TypeDef GPIOPortA;
extern "C" GPIO_TypeDef GPIOPortB;
extern "C" GPIO_TypeDef GPIOPortC;
extern "C" GPIO_TypeDef GPIOPortD;
extern "C" GPIO_TypeDef GPIOPortE;
extern "C" GPIO_TypeDef GPIOPortF;
extern "C" GPIO_TypeDef GPIOPortG;
extern "C" GPIO_TypeDef GPIOPortH;
extern "C" GPIO_TypeDef GPIOPortI;

template <GPIO_TypeDef& Port, uint16_t Pin>
class GPIO {
public:
    void config(uint32_t mode, uint32_t pull, uint32_t speed, uint32_t alt) {
        GPIO_InitTypeDef cfg = {
            .Pin = Pin,
            .Mode = mode,
            .Pull = pull,
            .Speed = speed,
            .Alternate = alt,
        };
        
        HAL_GPIO_Init(&Port, &cfg);
    }
    
    bool read() {
        return HAL_GPIO_ReadPin(&Port, Pin)==GPIO_PIN_SET;
    }
    
    void write(bool x) {
        HAL_GPIO_WritePin(&Port, Pin, (x ? GPIO_PIN_SET : GPIO_PIN_RESET));
    }
};
