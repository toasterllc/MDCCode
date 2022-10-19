#pragma once
#include "Toastbox/Task.h"
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Assert.h"

template <typename T_Scheduler>
class Battery {
public:
    using BAT_CHRG_LVL = GPIO<GPIOPortF, GPIO_PIN_3>;
    
    Battery() {}
    
    // Initialization
    void init() {
        // Configure global features of the ADC (clock, resolution,
        // data alignment, number of conversions)
        {
            _adc3.Instance = ADC3;
            _adc3.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV8;
            _adc3.Init.Resolution = ADC_RESOLUTION_12B;
            _adc3.Init.ScanConvMode = ADC_SCAN_DISABLE;
            _adc3.Init.ContinuousConvMode = DISABLE;
            _adc3.Init.DiscontinuousConvMode = DISABLE;
            _adc3.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
            _adc3.Init.ExternalTrigConv = ADC_SOFTWARE_START;
            _adc3.Init.DataAlign = ADC_DATAALIGN_RIGHT;
            _adc3.Init.NbrOfConversion = 1;
            _adc3.Init.DMAContinuousRequests = DISABLE;
            _adc3.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
            HAL_StatusTypeDef hs = HAL_ADC_Init(&_adc3);
            Assert(hs == HAL_OK);
        }
        
        // Configure ADC channel rank and sample time
        {
            ADC_ChannelConfTypeDef cfg = {};
            cfg.Channel = ADC_CHANNEL_9;
            cfg.Rank = ADC_REGULAR_RANK_1;
            cfg.SamplingTime = ADC_SAMPLETIME_480CYCLES;
            HAL_StatusTypeDef hs = HAL_ADC_ConfigChannel(&_adc3, &cfg);
            Assert(hs == HAL_OK);
        }
        
        // Enable ADC clocks
        {
            __HAL_RCC_ADC3_CLK_ENABLE();
            __HAL_RCC_GPIOF_CLK_ENABLE();
        }
        
        // Configure ADC callbacks
        {
            _adc3.Ctx = this;
            
            _adc3.ConvCpltCallback = [] (ADC_HandleTypeDef* me) {
                ((Battery*)me->Ctx)->_handleSampleDone();
            };
        }
        
        // Configure ADC interrupts
        {
            constexpr uint32_t InterruptPriority = 2; // Should be >0 so that SysTick can still preempt
            HAL_NVIC_SetPriority(ADC_IRQn, InterruptPriority, 0);
            HAL_NVIC_EnableIRQ(ADC_IRQn);
        }
        
        // Configure pins
        {
            BAT_CHRG_LVL::Config(GPIO_MODE_ANALOG, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        }
    }
    
    void isr() {
        ISR_HAL_ADC(&_adc3);
    }
    
    uint16_t voltageSample() {
        _busy = true;
        
        HAL_StatusTypeDef hs = HAL_ADC_Start_IT(&_adc3);
        Assert(hs == HAL_OK);
        
        T_Scheduler::Wait([&] { return !_busy; });
        
        return HAL_ADC_GetValue(&_adc3);
    }
    
private:
    void _handleSampleDone() {
        _busy = false;
    }
    
    ADC_HandleTypeDef _adc3;
    bool _busy = false;
};
