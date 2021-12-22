#pragma once
#include "GPIO.h"
#include "MSP430.h"
#include "Util.h"

class System {
public:
    static constexpr uint8_t CPUFreqMHz = 128;
    static constexpr uint32_t UsPerSysTick = 1000;
    
    static void InitLED() {
//        LED0::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED1::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED2::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
        LED3::Config(GPIO_MODE_OUTPUT_PP, GPIO_NOPULL, GPIO_SPEED_FREQ_LOW, 0);
    }
    
    static void Init() {
        // Reset peripherals, initialize flash interface, initialize SysTick
        HAL_Init();
        
        // Configure the system clock
        _ClockInit();
        
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
    using MSPTest = GPIO<GPIOPortB, GPIO_PIN_1>;
    using MSPRst_ = GPIO<GPIOPortB, GPIO_PIN_0>;
    static inline MSP430<MSPTest, MSPRst_, CPUFreqMHz> MSP;
    
    using ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    
    using ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
    using ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    
    // LEDs
//    using LED0 = GPIO<GPIOPortF, GPIO_PIN_14>;
    using LED1 = GPIO<GPIOPortE, GPIO_PIN_7>;
    using LED2 = GPIO<GPIOPortE, GPIO_PIN_10>;
    using LED3 = GPIO<GPIOPortE, GPIO_PIN_12>;
    
private:
    static void _ClockInit() {
        // Configure the main internal regulator output voltage
        {
            __HAL_RCC_PWR_CLK_ENABLE();
            __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE3);
        }
        
        // Initialize RCC oscillators
        {
            RCC_OscInitTypeDef cfg = {};
            cfg.OscillatorType = RCC_OSCILLATORTYPE_HSE;
            cfg.HSEState = RCC_HSE_BYPASS;
            cfg.PLL.PLLState = RCC_PLL_ON;
            cfg.PLL.PLLSource = RCC_PLLSOURCE_HSE;
            cfg.PLL.PLLM = 8;
            cfg.PLL.PLLN = 128;
            cfg.PLL.PLLP = RCC_PLLP_DIV2;
            cfg.PLL.PLLQ = 2;
            
            HAL_StatusTypeDef hr = HAL_RCC_OscConfig(&cfg);
            Assert(hr == HAL_OK);
        }
        
        // Initialize bus clocks for CPU, AHB, APB
        {
            RCC_ClkInitTypeDef cfg = {};
            cfg.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK|RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
            cfg.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
            cfg.AHBCLKDivider = RCC_SYSCLK_DIV1;
            cfg.APB1CLKDivider = RCC_HCLK_DIV4;
            cfg.APB2CLKDivider = RCC_HCLK_DIV2;
            
            HAL_StatusTypeDef hr = HAL_RCC_ClockConfig(&cfg, FLASH_LATENCY_6);
            Assert(hr == HAL_OK);
        }
        
        {
            RCC_PeriphCLKInitTypeDef cfg = {};
            cfg.PeriphClockSelection = RCC_PERIPHCLK_CLK48;
            cfg.PLLSAI.PLLSAIN = 96;
            cfg.PLLSAI.PLLSAIQ = 2;
            cfg.PLLSAI.PLLSAIP = RCC_PLLSAIP_DIV4;
            cfg.PLLSAIDivQ = 1;
            cfg.Clk48ClockSelection = RCC_CLK48SOURCE_PLLSAIP;
            
            HAL_StatusTypeDef hr = HAL_RCCEx_PeriphCLKConfig(&cfg);
            Assert(hr == HAL_OK);
        }
    }

};

// MARK: - IntState

bool Toastbox::IntState::InterruptsEnabled() {
    return !__get_PRIMASK();
}

void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __enable_irq();
    else __disable_irq();
}

void Toastbox::IntState::WaitForInterrupt() {
    Toastbox::IntState ints(true);
    __WFI();
}

// MARK: - Main Thread Stack

#define _StackMainSize 1024

[[gnu::section(".stack.main")]]
uint8_t _StackMain[_StackMainSize];

asm(".global _StackMainEnd");
asm(".equ _StackMainEnd, _StackMain+" Stringify(_StackMainSize));

// MARK: - Abort

extern "C" [[noreturn]]
void abort() {
    Toastbox::IntState ints(false);
    
    System::InitLED();
    for (bool x=true;; x=!x) {
        System::LED1::Write(x);
        System::LED2::Write(x);
        System::LED3::Write(x);
        for (volatile uint32_t i=0; i<(uint32_t)5000000; i++);
    }
}
