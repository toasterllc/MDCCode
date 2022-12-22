#pragma once
#include "stm32f7xx.h"
#include "Util.h"

#define GPIOPort(name, addr)                            \
    extern "C" GPIO_TypeDef name;                       \
    __asm__(                                            \
        ".global " #name                        "\n"    \
        ".equ    " #name ", " Stringify(addr)   "\n"    \
    )

GPIOPort(GPIOPortA, GPIOA_BASE);
GPIOPort(GPIOPortB, GPIOB_BASE);
GPIOPort(GPIOPortC, GPIOC_BASE);
GPIOPort(GPIOPortD, GPIOD_BASE);
GPIOPort(GPIOPortE, GPIOE_BASE);
GPIOPort(GPIOPortF, GPIOF_BASE);
GPIOPort(GPIOPortG, GPIOG_BASE);
GPIOPort(GPIOPortH, GPIOH_BASE);
GPIOPort(GPIOPortI, GPIOI_BASE);

template <GPIO_TypeDef& Port, uint16_t PinIdx>
class GPIO {
public:
    static constexpr uint16_t Bit = UINT16_C(1)<<PinIdx;
    
    static void Config(uint32_t mode, uint32_t pull, uint32_t speed, uint32_t alt) {
        GPIO_InitTypeDef cfg = {
            .Pin = Bit,
            .Mode = mode,
            .Pull = pull,
            .Speed = speed,
            .Alternate = alt,
        };
        
        HAL_GPIO_Init(&Port, &cfg);
    }
    
    static bool Read() {
        return HAL_GPIO_ReadPin(&Port, Bit)==GPIO_PIN_SET;
    }
    
    static void Write(bool x) {
        HAL_GPIO_WritePin(&Port, Bit, (x ? GPIO_PIN_SET : GPIO_PIN_RESET));
    }
};
