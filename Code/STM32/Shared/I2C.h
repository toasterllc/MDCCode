#pragma once
#include <atomic>
#include "stm32f7xx.h"

template <
typename T_Scheduler,
uint8_t T_Addr
>
class I2CType {
public:
    static void Init() {
        __HAL_RCC_GPIOB_CLK_ENABLE();
        
        _SCL::Config(GPIO_MODE_AF_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF4_I2C1);
        _SDA::Config(GPIO_MODE_AF_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF4_I2C1);
        
        __HAL_RCC_I2C1_CLK_ENABLE();
        HAL_NVIC_SetPriority(I2C1_EV_IRQn, 0, 0);
        HAL_NVIC_EnableIRQ(I2C1_EV_IRQn);
        HAL_NVIC_SetPriority(I2C1_ER_IRQn, 0, 0);
        HAL_NVIC_EnableIRQ(I2C1_ER_IRQn);
        
        _Device.MasterTxCpltCallback = [] (I2C_HandleTypeDef* me) {
            Assert(_Busy.load());
            _Busy = false;
        };
        
        _Device.MasterRxCpltCallback = [] (I2C_HandleTypeDef* me) {
            Assert(_Busy.load());
            _Busy = false;
        };
        
        _Device.ErrorCallback = [] (I2C_HandleTypeDef* me) {
            Assert(false);
        };
        
        _Device.AbortCpltCallback = [] (I2C_HandleTypeDef* me) {
            Assert(false);
        };
        
        HAL_StatusTypeDef hs = HAL_I2C_Init(&_Device);
        Assert(hs == HAL_OK);
        
        hs = HAL_I2CEx_ConfigAnalogFilter(&_Device, I2C_ANALOGFILTER_ENABLE);
        Assert(hs == HAL_OK);
        
        hs = HAL_I2CEx_ConfigDigitalFilter(&_Device, 0);
        Assert(hs == HAL_OK);
    }
    
    template <typename T>
    static void Send(const T& msg) {
        Assert(!_Busy.load());
        
        HAL_StatusTypeDef hs = HAL_I2C_Master_Transmit_IT(_Device, T_Addr, &msg, sizeof(msg));
        Assert(hs == HAL_OK);
        
        T_Scheduler::Wait([&] { return !_Busy.load(); });
    }
    
    template <typename T>
    static void Recv(T& msg) {
        Assert(!_Busy.load());
        
        HAL_StatusTypeDef hs = HAL_I2C_Master_Receive_IT(_Device, T_Addr, &msg, sizeof(msg));
        Assert(hs == HAL_OK);
        
        T_Scheduler::Wait([&] { return !_Busy.load(); });
    }
    
    static void ISR_Event() {
        ISR_HAL_I2C_EV(&_Device);
    }
    
    static void ISR_Error() {
        ISR_HAL_I2C_ER(&_Device);
    }
    
private:
    static inline std::atomic<bool> _Busy = false;
    
    static inline I2C_HandleTypeDef _Device = {
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
