#pragma once
#include "GPIO.h"
#include "SystemClock.h"
#include "MSP430.h"
#include "Util.h"

#warning TODO: rename to System
class SystemBase {
private:
    using _MSPTest = GPIO<GPIOPortB, GPIO_PIN_1>;
    using _MSPRst_ = GPIO<GPIOPortB, GPIO_PIN_0>;
    using _MSP430 = MSP430<_MSPTest,_MSPRst_,SystemClock::CPUFreqMHz>;

public:
    static void InitLED() {
//        LED0::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED1::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED2::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED3::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
    static void Init() {
        // Reset peripherals, initialize flash interface, initialize Systick
        HAL_Init();
        
        // Configure the system clock
        SystemClock::Init();
        
        // Allow debugging while we're asleep
        HAL_DBGMCU_EnableDBGSleepMode();
        HAL_DBGMCU_EnableDBGStopMode();
        HAL_DBGMCU_EnableDBGStandbyMode();
        
        // TODO: move these to their respective peripherals? there'll be some redundency though, is that OK?
        __HAL_RCC_GPIOB_CLK_ENABLE(); // USB, QSPI, LEDs
        __HAL_RCC_GPIOC_CLK_ENABLE(); // QSPI
        __HAL_RCC_GPIOE_CLK_ENABLE(); // LEDs
        __HAL_RCC_GPIOF_CLK_ENABLE(); // QSPI
        __HAL_RCC_GPIOG_CLK_ENABLE(); // QSPI
        __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE (clock input)
        
        // Configure our LEDs
        InitLED();
        
        // Init MSP
        MSP.init();
    }
    
    // TODO: we should also rename to MSPJTAG to make it clear that it's not for comms with the MSP app
    static inline _MSP430 MSP;
    
    // LEDs
//    using LED0 = GPIO<GPIOPortF, GPIO_PIN_14>;
    using LED1 = GPIO<GPIOPortE, GPIO_PIN_7>;
    using LED2 = GPIO<GPIOPortE, GPIO_PIN_10>;
    using LED3 = GPIO<GPIOPortE, GPIO_PIN_12>;
};

#warning verify that _StackMainSize is large enough
#define _StackMainSize 128

[[gnu::section(".stack.main")]]
uint8_t _StackMain[_StackMainSize];

asm(".global _StackMainEnd");
asm(".equ _StackMainEnd, _StackMain+" Stringify(_StackMainSize));

extern "C" [[noreturn]]
void abort() {
    Toastbox::IntState ints(false);
    
    SystemBase::InitLED();
    for (bool x=true;; x=!x) {
        SystemBase::LED1::Write(x);
        SystemBase::LED2::Write(x);
        SystemBase::LED3::Write(x);
        for (volatile uint32_t i=0; i<(uint32_t)5000000; i++);
    }
}
