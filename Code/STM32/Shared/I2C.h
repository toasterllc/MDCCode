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
        
        HAL_StatusTypeDef hs = HAL_I2C_Init(&_Device);
        Assert(hs == HAL_OK);
        
        hs = HAL_I2CEx_ConfigAnalogFilter(&_Device, I2C_ANALOGFILTER_ENABLE);
        Assert(hs == HAL_OK);
        
        hs = HAL_I2CEx_ConfigDigitalFilter(&_Device, 0);
        Assert(hs == HAL_OK);
    }
    
    template <typename T_Send, typename T_Recv>
    static bool Send(const T_Send& send, T_Recv& recv) {
        bool ok = _Send(send);
        if (!ok) return false;
        
        ok = _Recv(recv);
        if (!ok) return false;
        
        return true;
    }
    
    static void ISR_Event() {
        ISR_HAL_I2C_EV(&_Device);
    }
    
    static void ISR_Error() {
        ISR_HAL_I2C_ER(&_Device);
    }
    
private:
    enum class _State : uint8_t {
        Idle,
        Send,
        Recv,
        Error,
    };
    
    template <typename T>
    static bool _Send(const T& msg) {
        Assert(_St.load()==_State::Idle || _St.load()==_State::Error);
        
        _St = _State::Send;
        HAL_StatusTypeDef hs = HAL_I2C_Master_Transmit_IT(&_Device, T_Addr, (uint8_t*)&msg, sizeof(msg));
        Assert(hs == HAL_OK);
        
        T_Scheduler::Wait([&] { return _St.load() != _State::Send; });
        return _St.load()==_State::Idle;
    }
    
    template <typename T>
    static bool _Recv(T& msg) {
        Assert(_St.load()==_State::Idle || _St.load()==_State::Error);
        
        _St = _State::Recv;
        HAL_StatusTypeDef hs = HAL_I2C_Master_Receive_IT(&_Device, T_Addr, (uint8_t*)&msg, sizeof(msg));
        Assert(hs == HAL_OK);
        
        T_Scheduler::Wait([&] { return _St.load()!=_State::Recv; });
        return _St.load()==_State::Idle;
    }
    
    static void _CallbackTx(I2C_HandleTypeDef* me) {
        Assert(_St.load() == _State::Send);
        _St = _State::Idle;
    }
    
    static void _CallbackRx(I2C_HandleTypeDef* me) {
        Assert(_St.load() == _State::Recv);
        _St = _State::Idle;
    }
    
    static void _CallbackError(I2C_HandleTypeDef* me) {
        Assert(_St.load()==_State::Send || _St.load()==_State::Recv);
        _St = _State::Error;
    }
    
    static void _CallbackAbort(I2C_HandleTypeDef* me) {
        // Should never occur
        Assert(false);
    }
    
    static inline std::atomic<_State> _St = _State::Idle;
    
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
        
        .MasterTxCpltCallback   = _CallbackTx,
        .MasterRxCpltCallback   = _CallbackRx,
        .ErrorCallback          = _CallbackError,
        .AbortCpltCallback      = _CallbackAbort,
    };
    
    using _SCL = GPIO<GPIOPortB, 8>;
    using _SDA = GPIO<GPIOPortB, 9>;
};
