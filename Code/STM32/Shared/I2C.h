#pragma once
#include <atomic>
#include "stm32f7xx.h"
#include "Toastbox/Defer.h"

template <
typename T_Scheduler,
uint8_t T_Addr
>
class I2CType {
public:
    static void Init() {
        // Enable clock for SCL/SDA GPIOs (B8/B9)
        __HAL_RCC_GPIOB_CLK_ENABLE();
        
        _SCL::Config(GPIO_MODE_AF_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF4_I2C1);
        _SDA::Config(GPIO_MODE_AF_OD, GPIO_NOPULL, GPIO_SPEED_FREQ_VERY_HIGH, GPIO_AF4_I2C1);
        
        __HAL_RCC_I2C1_CLK_ENABLE();
        
        constexpr uint32_t InterruptPriority = 1; // Should be >0 so that SysTick can still preempt
        HAL_NVIC_SetPriority(I2C1_EV_IRQn, InterruptPriority, 0);
        HAL_NVIC_EnableIRQ(I2C1_EV_IRQn);
        HAL_NVIC_SetPriority(I2C1_ER_IRQn, InterruptPriority, 0);
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
        // "address ... must be shifted to the left before calling"
        constexpr uint16_t Addr = T_Addr<<1;
        constexpr int AttemptCount = 5;
        constexpr int AttemptDelayMs = 200;
        
        // Reset _St upon return
        Defer( _St = _State::Idle; );
        
        // Wait until we're idle
        T_Scheduler::Wait([&] { return _St.load() == _State::Idle; });
        _St = _State::Busy;
        
        // Try up to `AttemptCount` times to get an ACK
        for (int i=0; i<AttemptCount; i++) {
            HAL_StatusTypeDef hs = HAL_I2C_Master_Transmit_IT(&_Device, Addr, (uint8_t*)&send, sizeof(send));
            Assert(hs == HAL_OK);
            
            T_Scheduler::Wait([&] { return _St.load() != _State::Busy; });
            if (_St.load() == _State::Done) {
                break;
            } else if (i != AttemptCount-1) {
                T_Scheduler::Sleep(T_Scheduler::Ms(AttemptDelayMs));
            } else {
                // This was the final attempt and it failed; bail
                return false;
            }
        }
        
        _St = _State::Busy;
        HAL_StatusTypeDef hs = HAL_I2C_Master_Receive_IT(&_Device, Addr, (uint8_t*)&recv, sizeof(recv));
        Assert(hs == HAL_OK);
        
        T_Scheduler::Wait([&] { return _St.load() != _State::Busy; });
        if (_St.load() != _State::Done) return false;
        
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
        Busy,
        Done,
        Error,
    };
    
    static void _CallbackTxRx(I2C_HandleTypeDef* me) {
        Assert(_St.load() == _State::Busy);
        _St = _State::Done;
    }
    
    static void _CallbackError(I2C_HandleTypeDef* me) {
        Assert(_St.load() == _State::Busy);
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
            .Timing             = 0x00100413, // SCL = 1 MHz
            .OwnAddress1        = 0,
            .AddressingMode     = I2C_ADDRESSINGMODE_7BIT,
            .DualAddressMode    = I2C_DUALADDRESS_DISABLE,
            .OwnAddress2        = 0,
            .OwnAddress2Masks   = I2C_OA2_NOMASK,
            .GeneralCallMode    = I2C_GENERALCALL_DISABLE,
            .NoStretchMode      = I2C_NOSTRETCH_DISABLE,
        },
        
        .MasterTxCpltCallback   = _CallbackTxRx,
        .MasterRxCpltCallback   = _CallbackTxRx,
        .ErrorCallback          = _CallbackError,
        .AbortCpltCallback      = _CallbackAbort,
    };
    
    using _SCL = GPIO<GPIOPortB, 8>;
    using _SDA = GPIO<GPIOPortB, 9>;
};
