#include <cstring>
#include "stm32f7xx.h"

QSPI_HandleTypeDef _device;
DMA_HandleTypeDef _dma;

extern "C" __attribute__((section(".isr"))) void ISR_SysTick() {
}

extern "C" __attribute__((section(".isr"))) void ISR_QUADSPI() {
    ISR_HAL_QSPI(&_device);
}

extern "C" __attribute__((section(".isr"))) void ISR_DMA2_Stream7() {
    ISR_HAL_DMA(&_dma);
}

extern "C" __attribute__((section(".isr"))) void ISR_DMA2_Stream4() {
    for (;;);
}

[[gnu::section(".stack.main")]] uint8_t _StackMain[1024];
asm(".global _StackMainEnd");
asm(".equ _StackMainEnd, _StackMain+1024");


extern "C" void __libc_init_array();

extern "C" void StartupRun() {
    // Cache RCC_CSR since we're about to clear it
    auto csr = READ_REG(RCC->CSR);
    // Clear RCC_CSR by setting the RMVF bit
    SET_BIT(RCC->CSR, RCC_CSR_RMVF);
    
    extern uint8_t _sdata_flash[];
    extern uint8_t _sdata_ram[];
    extern uint8_t _edata_ram[];
    extern uint8_t _sbss[];
    extern uint8_t _ebss[];
    extern uint8_t VectorTable[];
    extern int main() __attribute__((noreturn));
    
    // Copy .data section from flash to RAM
    memcpy(_sdata_ram, _sdata_flash, _edata_ram-_sdata_ram);
    // Zero .bss section
    memset(_sbss, 0, _ebss-_sbss);
    
    // FPU settings
    if (__FPU_PRESENT && __FPU_USED) {
        SCB->CPACR |= ((3UL << 10*2)|(3UL << 11*2));  // Set CP10 and CP11 Full Access
    }
    
    // Set the vector table address
    __disable_irq();
    SCB->VTOR = (uint32_t)VectorTable;
    __DSB();
    __enable_irq();
    
    // Call static constructors
    __libc_init_array();
    
    // Call main function
    main();
    
    // Loop forever if main returns
    for (;;);
}

int main() {
    static const uint8_t ff = 0xff;
    
    constexpr uint32_t InterruptPriority = 1; // Should be >0 so that SysTick can still preempt
    
    // Reset peripherals, initialize flash interface, initialize Systick
    HAL_Init();
    
    // Configure the system clock
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
    
    __HAL_RCC_GPIOI_CLK_ENABLE(); // ICE_CRST_, ICE_CDONE
    
    // DMA clock/IRQ
    __HAL_RCC_DMA2_CLK_ENABLE();
    HAL_NVIC_SetPriority(DMA2_Stream7_IRQn, InterruptPriority, 0);
    HAL_NVIC_EnableIRQ(DMA2_Stream7_IRQn);
    
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
    
    // Init DMA
    _dma.Instance = DMA2_Stream7;
    _dma.Init.Channel = DMA_CHANNEL_3;
    _dma.Init.Direction = DMA_MEMORY_TO_PERIPH;
    _dma.Init.PeriphInc = DMA_PINC_DISABLE;
    _dma.Init.MemInc = DMA_MINC_ENABLE;
    _dma.Init.PeriphDataAlignment = DMA_PDATAALIGN_BYTE;
    _dma.Init.MemDataAlignment = DMA_MDATAALIGN_BYTE;
    _dma.Init.Mode = DMA_NORMAL;
    _dma.Init.Priority = DMA_PRIORITY_VERY_HIGH;
    _dma.Init.FIFOMode = DMA_FIFOMODE_ENABLE;
    _dma.Init.FIFOThreshold = DMA_FIFO_THRESHOLD_HALFFULL;
    _dma.Init.MemBurst = DMA_MBURST_SINGLE;
    _dma.Init.PeriphBurst = DMA_PBURST_SINGLE;
    
    hs = HAL_DMA_Init(&_dma);
    Assert(hs == HAL_OK);
    
    __HAL_LINKDMA(&_device, hdma, _dma);
    
    
    
    
    
    
    QSPI_CommandTypeDef cmd = {
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
    
    hs = HAL_QSPI_Transmit_DMA(&_device, (uint8_t*)&ff);
    Assert(hs == HAL_OK);
    
    for (;;);
    return 0;
}
