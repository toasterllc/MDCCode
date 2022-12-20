#pragma once
#include "Toastbox/Task.h"
#include "stm32f7xx.h"
#include "GPIO.h"
#include "Assert.h"
#include "STM.h"

template <typename T_Scheduler>
class Battery {
public:
    using BAT_CHRG_STAT = GPIO<GPIOPortE, GPIO_PIN_15>;
    
    Battery() {}
    
    // Initialization
    void init() {
        // Enable GPIO clocks
        {
            __HAL_RCC_GPIOE_CLK_ENABLE();
        }
        
        // Configure GPIOs
        {
            BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLDOWN, GPIO_SPEED_FREQ_LOW, 0);
        }
    }
    
    STM::BatteryStatus status() {
        #warning TODO: on Rev7 board:
        #warning TODO: to sample the battery voltage, we'll need to enable the voltage divider, sample the battery voltage, and then disable the voltage divider.
        #warning TODO: and we only sample the battery voltage if _chargeStatus() == Underway|Complete! this is because the voltage divider circuitry breaks MCP73831T's battery-detection when no battery is connected.
        return {
            .chargeStatus = _chargeStatus(),
            .voltage = 0,
        };
    }
    
private:
    STM::BatteryStatus::ChargeStatus _chargeStatus() {
        using namespace STM;
        
        // The battery charger IC (MCP73831T-2ACI/OT) has tristate output, where:
        //   high-z: shutdown / no battery
        //   low: charging underway
        //   high: charging complete
        // To sense these 3 different states, we configure our GPIO with a pullup
        // and read the value of the pin, repeat with a pulldown, and compare the
        // read values.
        BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLUP, GPIO_SPEED_FREQ_LOW, 0);
        T_Scheduler::Sleep(T_Scheduler::Ms(10));
        const bool a = BAT_CHRG_STAT::Read();
        
        BAT_CHRG_STAT::Config(GPIO_MODE_INPUT, GPIO_PULLDOWN, GPIO_SPEED_FREQ_LOW, 0);
        T_Scheduler::Sleep(T_Scheduler::Ms(10));
        const bool b = BAT_CHRG_STAT::Read();
        
        if (a != b) {
            // BAT_CHRG_STAT == high-z
            return BatteryStatus::ChargeStatuses::Shutdown;
        } else {
            if (!a) {
                // BAT_CHRG_STAT == low
                return BatteryStatus::ChargeStatuses::Underway;
            } else {
                // BAT_CHRG_STAT == high
                return BatteryStatus::ChargeStatuses::Complete;
            }
        }
    }
};
