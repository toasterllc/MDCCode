#include "GPIO.h"
#include "SystemClock.h"
#include "MSP430.h"

template <typename T>
class SystemBase {
public:
    SystemBase() {}

protected:
    void init() {
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
        _LED2::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _LED3::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
    using _MSPTest = GPIO<GPIOPortE, GPIO_PIN_12>;
    using _MSPRst_ = GPIO<GPIOPortE, GPIO_PIN_15>;
    MSP430<_MSPTest,_MSPRst_,SystemClock::CPUFreqMHz> _msp;
    
    // LEDs
    using _LED2 = GPIO<GPIOPortB, GPIO_PIN_10>;
    using _LED3 = GPIO<GPIOPortB, GPIO_PIN_11>;
};
