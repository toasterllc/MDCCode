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
        _LED0::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _LED1::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _LED2::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _LED3::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
    [[noreturn]] void abort() {
        for (bool x=true;; x=!x) {
            _LED0::Write(x);
            _LED1::Write(x);
            _LED2::Write(x);
            _LED3::Write(x);
            HAL_Delay(500);
        }
    }
    
    using _MSPTest = GPIO<GPIOPortB, GPIO_PIN_1>;
    using _MSPRst_ = GPIO<GPIOPortB, GPIO_PIN_0>;
    // TODO: move this to STLoader's system
    // TODO: we should also rename to MSPJTAG to make it clear that it's not for comms with the MSP app
    MSP430<_MSPTest,_MSPRst_,SystemClock::CPUFreqMHz> _msp;
    
    // LEDs
    using _LED0 = GPIO<GPIOPortF, GPIO_PIN_14>;
    using _LED1 = GPIO<GPIOPortE, GPIO_PIN_7>;
    using _LED2 = GPIO<GPIOPortE, GPIO_PIN_10>;
    using _LED3 = GPIO<GPIOPortE, GPIO_PIN_12>;
    
    friend void abort();
};
