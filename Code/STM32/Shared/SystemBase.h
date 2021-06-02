#include "GPIO.h"
#include "SystemClock.h"

template <typename T>
class SystemBase {
public:
    SystemBase() :
    _mspTest(GPIOE, GPIO_PIN_12),
    _mspRst_(GPIOE, GPIO_PIN_15),
    _led2(GPIOB, GPIO_PIN_10),
    _led3(GPIOB, GPIO_PIN_11) {
    }

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
        _mspTest.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _mspRst_.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _led2.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        _led3.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
    // LEDs
    GPIO _mspTest;
    GPIO _mspRst_;
    GPIO _led2;
    GPIO _led3;
};
