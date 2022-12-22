#pragma once
#include "stm32f7xx.h"

template <typename T_Scheduler>
class I2CType {
public:
    static void Init() {
        __HAL_RCC_GPIOB_CLK_ENABLE();
        
        _SCL::Config(GPIO_MODE_AF_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF4_I2C1);
        _SDA::Config(GPIO_MODE_AF_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF4_I2C1);
        
        __HAL_RCC_I2C1_CLK_ENABLE();
        
        HAL_StatusTypeDef hs = HAL_I2C_Init(&_device);
        Assert(hs == HAL_OK);
        
        hs = HAL_I2CEx_ConfigAnalogFilter(&_device, I2C_ANALOGFILTER_ENABLE);
        Assert(hs == HAL_OK);
        
        hs = HAL_I2CEx_ConfigDigitalFilter(&_device, 0);
        Assert(hs == HAL_OK);
    }
    
    template <typename T>
    static void Send(const T& msg) {
        
    }
    
    template <typename T>
    static void Recv(T& msg) {
        
    }
    
private:
    static inline I2C_HandleTypeDef _device = {
        .Instance               = I2C1,
        .Init = {
            .Timing             = 0x00707CBB,
            .OwnAddress1        = 0,
            .AddressingMode     = I2C_ADDRESSINGMODE_7BIT,
            .DualAddressMode    = I2C_DUALADDRESS_DISABLE,
            .OwnAddress2        = 0,
            .OwnAddress2Masks   = I2C_OA2_NOMASK,
            .GeneralCallMode    = I2C_GENERALCALL_DISABLE,
            .NoStretchMode      = I2C_NOSTRETCH_DISABLE,
        },
    };
    using _SCL = GPIO<GPIOPortB, 8>;
    using _SDA = GPIO<GPIOPortB, 9>;
};
