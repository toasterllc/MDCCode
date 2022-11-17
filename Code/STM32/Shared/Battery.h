#pragma once
#include "Toastbox/Task.h"
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Assert.h"
#include "STM.h"

template <typename T_Scheduler>
class Battery {
public:
    using BAT_CHRG_STAT = GPIO<GPIOPortB, GPIO_PIN_11>;
    using BAT_CHRG_LVL = GPIO<GPIOPortF, GPIO_PIN_3>;
    
    Battery() {}
    
    // Initialization
    void init() {
        // Enable ADC+GPIO clocks
        {
            __HAL_RCC_ADC3_CLK_ENABLE();
            __HAL_RCC_GPIOE_CLK_ENABLE();
            __HAL_RCC_GPIOF_CLK_ENABLE();
        }
        
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
        
        // Configure GPIOs
        {
            BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLDOWN, GPIO_SPEED_FREQ_LOW, 0);
            BAT_CHRG_LVL::Config(GPIO_MODE_ANALOG, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        }
    }
    
    void isr() {
        ISR_HAL_ADC(&_adc3);
    }
    
    STM::BatteryStatus status() {
        #warning TODO: on Rev7 board:
        #warning TODO: to sample the battery voltage, we'll need to enable the voltage divider, sample the battery voltage, and then disable the voltage divider.
        #warning TODO: and we only sample the battery voltage if _chargeStatus() == Underway|Complete! this is because the voltage divider circuitry breaks MCP73831T's battery-detection when no battery is connected.
        return {
            .chargeStatus = _chargeStatus(),
            .voltage = _voltageSample(),
        };
    }
    
private:
    STM::BatteryStatus::ChargeStatus _chargeStatus() {
        return STM::BatteryStatus::ChargeStatuses::Invalid;
//        using namespace STM;
//        
//        // The battery charger IC (MCP73831T-2ACI/OT) has tristate output, where:
//        //   high-z: shutdown / no battery
//        //   low: charging underway
//        //   high: charging complete
//        // To sense these 3 different states, we configure our GPIO with a pullup
//        // and read the value of the pin, and then repeat with a pulldown, and
//        // compare the read values.
//        BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLUP, GPIO_SPEED_FREQ_LOW, 0);
//        T_Scheduler::Sleep(T_Scheduler::Ms(10));
//        const bool a = BAT_CHRG_STAT::Read();
//        
//        BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLDOWN, GPIO_SPEED_FREQ_LOW, 0);
//        T_Scheduler::Sleep(T_Scheduler::Ms(10));
//        const bool b = BAT_CHRG_STAT::Read();
//        
//        if (a != b) {
//            // BAT_CHRG_STAT == high-z
//            return BatteryStatus::ChargeStatuses::Shutdown;
//        } else {
//            if (!a) {
//                // BAT_CHRG_STAT == low
//                return BatteryStatus::ChargeStatuses::Underway;
//            } else {
//                // BAT_CHRG_STAT == high
//                return BatteryStatus::ChargeStatuses::Complete;
//            }
//        }
    }
    
    uint16_t _voltageSample() {
//        HAL_StatusTypeDef hs = HAL_ADC_Start(&_adc3);
//        Assert(hs == HAL_OK);
//        
//        hs = HAL_ADC_PollForConversion(&_adc3, HAL_MAX_DELAY);
//        Assert(hs == HAL_OK);
//        
//        return HAL_ADC_GetValue(&_adc3);
        
        
        _busy = true;
        
        HAL_StatusTypeDef hs = HAL_ADC_Start_IT(&_adc3);
        Assert(hs == HAL_OK);
        
        T_Scheduler::Wait([&] { return !_busy; });
        
        const uint32_t sample = HAL_ADC_GetValue(&_adc3);
        
        constexpr uint32_t SampleMax = (1<<12)-1; // 12-bit samples
        constexpr uint32_t VoltageMaxMillivolts = 1800;
        constexpr uint32_t VoltageDividerNumer = 500; // We have a 2/5 voltage divider at the ADC input
        constexpr uint32_t VoltageDividerDenom = 200; // We have a 2/5 voltage divider at the ADC input
        return (sample * VoltageMaxMillivolts * VoltageDividerNumer) / (SampleMax * VoltageDividerDenom);
    }
    
    void _handleSampleDone() {
        _busy = false;
    }
    
    ADC_HandleTypeDef _adc3;
    bool _busy = false;
};
