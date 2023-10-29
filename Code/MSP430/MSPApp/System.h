#pragma once
#include "GPIO.h"
#include "Debug.h"

struct _Pin {
    // Port A
    using VDD_B_1V8_IMG_SD_EN       = GPIO::PortA::Pin<0x0, GPIO::Option::Output0>;
    using LED_SIGNAL                = GPIO::PortA::Pin<0x1, GPIO::Option::Output1>;
    using MSP_STM_I2C_SDA           = GPIO::PortA::Pin<0x2>;
    using MSP_STM_I2C_SCL           = GPIO::PortA::Pin<0x3>;
    using ICE_MSP_SPI_DATA_OUT      = GPIO::PortA::Pin<0x4>;
    using ICE_MSP_SPI_DATA_IN       = GPIO::PortA::Pin<0x5>;
    using ICE_MSP_SPI_CLK           = GPIO::PortA::Pin<0x6>;
    using BAT_CHRG_LVL              = GPIO::PortA::Pin<0x7, GPIO::Option::Input>; // No pullup/pulldown because this is an analog input (and the voltage divider provides a physical pulldown)
    using MSP_XOUT                  = GPIO::PortA::Pin<0x8>;
    using MSP_XIN                   = GPIO::PortA::Pin<0x9>;
    using LED_SEL                   = GPIO::PortA::Pin<0xA, GPIO::Option::Output0>;
    using VDD_B_2V8_IMG_SD_EN       = GPIO::PortA::Pin<0xB, GPIO::Option::Output0>;
    using MOTION_SIGNAL             = GPIO::PortA::Pin<0xC>;
    using BUTTON_SIGNAL_            = GPIO::PortA::Pin<0xD>;
    using BAT_CHRG_LVL_EN           = GPIO::PortA::Pin<0xE, GPIO::Option::Output0>;
    using VDD_B_3V3_STM             = GPIO::PortA::Pin<0xF>;
    
    // Port B
    using MOTION_EN_                = GPIO::PortB::Pin<0x0>;
    using VDD_B_EN                  = GPIO::PortB::Pin<0x1, GPIO::Option::Output0>;
    using _UNUSED0                  = GPIO::PortB::Pin<0x2>;
};

class _TaskPower;
class _TaskI2C;
class _TaskButton;
class _TaskMotion;
class _TaskLED;
class _TaskEvent;
class _TaskSD;
class _TaskImg;

static constexpr uint32_t _XT1FreqHz        = 32768;        // 32.768 kHz
static constexpr uint32_t _ACLKFreqHz       = _XT1FreqHz;   // 32.768 kHz
static constexpr uint32_t _MCLKFreqHz       = 16000000;     // 16 MHz
static constexpr uint32_t _SysTickFreqHz    = 2048;         // 2.048 kHz

static void _Sleep();

[[noreturn]]
void _SchedulerStackOverflow(size_t taskIdx);

#warning TODO: disable stack guard for production
static constexpr size_t _StackGuardCount = 16;

using _Scheduler = Toastbox::Scheduler<
    std::ratio<1, _SysTickFreqHz>,              // T_TickPeriod: time period between ticks
    
    _Sleep,                                     // T_Sleep: function to put processor to sleep;
                                                //          invoked when no tasks have work to do
    
    _StackGuardCount,                           // T_StackGuardCount: number of pointer-sized stack guard elements to use
    _SchedulerStackOverflow,                    // T_StackOverflow: function to handle stack overflow
    nullptr,                                    // T_StackInterrupt: unused
    
    // T_Tasks: list of tasks
    _TaskPower,
    _TaskI2C,
    _TaskButton,
    _TaskMotion,
    _TaskLED,
    _TaskEvent,
    _TaskSD,
    _TaskImg
>;
