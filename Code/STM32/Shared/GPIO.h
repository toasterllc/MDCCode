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
        
        // Call HAL_GPIO_DeInit in case the interrupt was previously configured as an interrupt source.
        // If we didn't call HAL_GPIO_DeInit(), then interrupts would remain enabled.
        #warning TODO: reduce overhead of configuring GPIOs. we shouldn't need to de-init/init everytime,
        #warning TODO: and we should be able to init all GPIOs simultaneously, like with MSPApp.
        
        #warning TODO: also, automatically call __HAL_RCC_GPIOX_CLK_ENABLE
        HAL_GPIO_DeInit(&Port, Bit);
        HAL_GPIO_Init(&Port, &cfg);
    }
    
    static bool Read() {
        return HAL_GPIO_ReadPin(&Port, Bit)==GPIO_PIN_SET;
    }
    
    static void Write(bool x) {
        HAL_GPIO_WritePin(&Port, Bit, (x ? GPIO_PIN_SET : GPIO_PIN_RESET));
    }
    
    static bool InterruptClear() {
        if (!(EXTI->PR & Bit)) return false;
        // Clear interrupt
        EXTI->PR = Bit;
        return true;
    }
};
