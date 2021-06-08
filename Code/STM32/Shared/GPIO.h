#pragma once
#include "stm32f7xx.h"

#define GPIOPort(name, addr)                            \
    extern GPIO_TypeDef name;                           \
    asm(".global _" #name "; .equ _" #name ", " #addr)

GPIOPort(GPIOPortA, GPIOA_BASE);
GPIOPort(GPIOPortB, GPIOB_BASE);
GPIOPort(GPIOPortC, GPIOC_BASE);
GPIOPort(GPIOPortD, GPIOD_BASE);
GPIOPort(GPIOPortE, GPIOE_BASE);
GPIOPort(GPIOPortF, GPIOF_BASE);
GPIOPort(GPIOPortG, GPIOG_BASE);
GPIOPort(GPIOPortH, GPIOH_BASE);
GPIOPort(GPIOPortI, GPIOI_BASE);

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
