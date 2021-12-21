#include "SystemClock.h"

QSPI_HandleTypeDef _device;
DMA_HandleTypeDef _dma;

extern "C" [[gnu::section(".isr")]] void ISR_QUADSPI() {
    ISR_HAL_QSPI(&_device);
}

extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream7() {
    ISR_HAL_DMA(&_dma);
}




extern "C" [[gnu::section(".isr")]] void ISR_NMI() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_HardFault() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_MemManage() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_BusFault() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_UsageFault() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SVC() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DebugMon() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_PendSV() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SysTick() {
//    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_WWDG() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_PVD() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TAMP_STAMP() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_RTC_WKUP() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_FLASH() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_RCC() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_EXTI0() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_EXTI1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_EXTI2() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_EXTI3() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_EXTI4() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream0() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream2() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream3() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream4() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream5() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream6() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_ADC() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_CAN1_TX() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_CAN1_RX0() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_CAN1_RX1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_CAN1_SCE() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_EXTI9_5() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM1_BRK_TIM9() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM1_UP_TIM10() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM1_TRG_COM_TIM11() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM1_CC() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM2() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM3() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM4() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_I2C1_EV() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_I2C1_ER() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_I2C2_EV() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_I2C2_ER() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SPI1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SPI2() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_USART1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_USART2() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_USART3() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_EXTI15_10() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_RTC_Alarm() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_OTG_FS_WKUP() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM8_BRK_TIM12() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM8_UP_TIM13() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM8_TRG_COM_TIM14() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM8_CC() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA1_Stream7() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_FMC() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SDMMC1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM5() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SPI3() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_UART4() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_UART5() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM6_DAC() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_TIM7() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream0() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream2() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream3() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream4() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_OTG_FS() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream5() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream6() {
    for (;;);
}
//extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream7() {
//    for (;;);
//}
extern "C" [[gnu::section(".isr")]] void ISR_USART6() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_I2C3_EV() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_I2C3_ER() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_OTG_HS_EP1_OUT() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_OTG_HS_EP1_IN() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_OTG_HS_WKUP() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_OTG_HS() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_AES() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_RNG() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_FPU() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_UART7() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_UART8() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SPI4() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SPI5() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SAI1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SAI2() {
    for (;;);
}
//extern "C" [[gnu::section(".isr")]] void ISR_QUADSPI() {
//    for (;;);
//}
extern "C" [[gnu::section(".isr")]] void ISR_LPTIM1() {
    for (;;);
}
extern "C" [[gnu::section(".isr")]] void ISR_SDMMC2() {
    for (;;);
}







[[gnu::section(".stack.main")]] uint8_t _StackMain[1024];
asm(".global _StackMainEnd");
asm(".equ _StackMainEnd, _StackMain+1024");



int main() {
    // Reset peripherals, initialize flash interface, initialize Systick
    HAL_Init();
    
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
    
    // TODO: move these to their respective peripherals? there'll be some redundency though, is that OK?
    __HAL_RCC_GPIOB_CLK_ENABLE(); // USB, QSPI, LEDs
    __HAL_RCC_GPIOC_CLK_ENABLE(); // QSPI
    __HAL_RCC_GPIOE_CLK_ENABLE(); // LEDs
    __HAL_RCC_GPIOF_CLK_ENABLE(); // QSPI
    __HAL_RCC_GPIOG_CLK_ENABLE(); // QSPI
    __HAL_RCC_GPIOH_CLK_ENABLE(); // HSE (clock input)
    
    
    
    
    
    
    
    
    constexpr uint32_t InterruptPriority = 1; // Should be >0 so that SysTick can still preempt
    
//    // DMA clock/IRQ
//    __HAL_RCC_DMA2_CLK_ENABLE();
//    HAL_NVIC_SetPriority(DMA2_Stream7_IRQn, InterruptPriority, 0);
//    HAL_NVIC_EnableIRQ(DMA2_Stream7_IRQn);
    
    // QSPI clock/IRQ
    __HAL_RCC_QSPI_CLK_ENABLE();
    __HAL_RCC_QSPI_FORCE_RESET();
    __HAL_RCC_QSPI_RELEASE_RESET();
    HAL_NVIC_SetPriority(QUADSPI_IRQn, InterruptPriority, 0);
    HAL_NVIC_EnableIRQ(QUADSPI_IRQn);
    
    // Init QUADSPI
    _device.Instance = QUADSPI;
    _device.Init.ClockPrescaler = 5; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1)
    _device.Init.FifoThreshold = 4;
    _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
//    _device.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_HALFCYCLE;
    _device.Init.FlashSize = 31; // Flash size is 31+1 address bits => 2^(31+1) bytes
    _device.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE;
    _device.Init.ClockMode = QSPI_CLOCK_MODE_0; // Clock idles low
//    _device.Init.ClockMode = QSPI_CLOCK_MODE_3; // Clock idles high
    _device.Init.FlashID = QSPI_FLASH_ID_1;
    _device.Init.DualFlash = QSPI_DUALFLASH_DISABLE;
    _device.Ctx = nullptr;
    
    HAL_StatusTypeDef hs = HAL_QSPI_Init(&_device);
    Assert(hs == HAL_OK);
    
//    // Init DMA
//    _dma.Instance = DMA2_Stream7;
//    _dma.Init.Channel = DMA_CHANNEL_3;
//    _dma.Init.Direction = DMA_MEMORY_TO_PERIPH;
//    _dma.Init.PeriphInc = DMA_PINC_DISABLE;
//    _dma.Init.MemInc = DMA_MINC_ENABLE;
//    _dma.Init.PeriphDataAlignment = DMA_PDATAALIGN_BYTE;
//    _dma.Init.MemDataAlignment = DMA_MDATAALIGN_BYTE;
//    _dma.Init.Mode = DMA_NORMAL;
//    _dma.Init.Priority = DMA_PRIORITY_VERY_HIGH;
//    _dma.Init.FIFOMode = DMA_FIFOMODE_ENABLE;
//    _dma.Init.FIFOThreshold = DMA_FIFO_THRESHOLD_HALFFULL;
//    _dma.Init.MemBurst = DMA_MBURST_SINGLE;
//    _dma.Init.PeriphBurst = DMA_PBURST_SINGLE;
//    
//    hs = HAL_DMA_Init(&_dma);
//    Assert(hs == HAL_OK);
//    
//    __HAL_LINKDMA(&_device, hdma, _dma);
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    // Send 8 clocks and wait for them to complete
    alignas(64) static const uint8_t ff = 0xff;
    
    const QSPI_CommandTypeDef cmd = {
        .Instruction = 0,
        .InstructionMode = QSPI_INSTRUCTION_NONE,
        
        .Address = 0,
        .AddressSize = QSPI_ADDRESS_8_BITS,
        .AddressMode = QSPI_ADDRESS_NONE,
        
        .AlternateBytes = 0,
        .AlternateBytesSize = QSPI_ALTERNATE_BYTES_8_BITS,
        .AlternateByteMode = QSPI_ALTERNATE_BYTES_NONE,
        
        .DummyCycles = 0,
        
        .NbData = (uint32_t)sizeof(ff),
        .DataMode = QSPI_DATA_1_LINE,
        
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
    
    hs = HAL_QSPI_Command(&_device, &cmd, HAL_MAX_DELAY);
    Assert(hs == HAL_OK);
    
    hs = HAL_QSPI_Transmit(&_device, (uint8_t*)&ff, HAL_MAX_DELAY);
    Assert(hs == HAL_OK);
    
//    hs = HAL_QSPI_Transmit_DMA(&_device, (uint8_t*)&ff);
//    Assert(hs == HAL_OK);
    
    for (;;);
    return 0;
}
