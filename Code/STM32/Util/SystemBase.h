#include "USB.h"
#include "QSPI.h"
#include "GPIO.h"
#include "SystemClock.h"

template <typename T>
class SystemBase {
public:
    SystemBase() :
    led0(GPIOE, GPIO_PIN_12),
    led1(GPIOE, GPIO_PIN_15),
    led2(GPIOB, GPIO_PIN_10),
    led3(GPIOB, GPIO_PIN_11) {
    }
    
    void init() {
        // Reset peripherals, initialize flash interface, initialize Systick
        HAL_Init();
        
        // Configure the system clock
        SystemClock::Init();
        
        // Allow debugging while we're asleep
        HAL_EnableDBGSleepMode();
        HAL_EnableDBGStopMode();
        HAL_EnableDBGStandbyMode();
        
        __HAL_RCC_GPIOB_CLK_ENABLE(); // USB, QSPI, LEDs
        __HAL_RCC_GPIOC_CLK_ENABLE(); // QSPI
        __HAL_RCC_GPIOE_CLK_ENABLE(); // LEDs
        __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE (clock input)
        
        // Configure our LEDs
        led0.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        led1.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        led2.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        led3.config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        
        // Initialize USB
        usb.init();
        
        // Initialize QSPI
        qspi.init();
    }
    
    // Peripherals
    USB usb;
    QSPI qspi;
    
    // LEDs
    GPIO led0;
    GPIO led1;
    GPIO led2;
    GPIO led3;
};
