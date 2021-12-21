#include "QSPI.h"
#include "Toastbox/IntState.h"
#include "SystemClock.h"

// QSPI clock divider=5 => run QSPI clock at 21.3 MHz
// QSPI alignment=byte, so we can transfer single bytes at a time
QSPI _QSPI(QSPI::Mode::Single, 5, QSPI::Align::Byte, QSPI::ChipSelect::Controlled);

extern "C" [[gnu::section(".isr")]] void ISR_QUADSPI() {
    _QSPI.isrQSPI();
}

extern "C" [[gnu::section(".isr")]] void ISR_DMA2_Stream7() {
    _QSPI.isrDMA();
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







static void _ice_qspiWrite(const void* data, size_t len) {
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
        
        .NbData = (uint32_t)len,
        .DataMode = QSPI_DATA_1_LINE,
        
        .DdrMode = QSPI_DDR_MODE_DISABLE,
        .DdrHoldHalfCycle = QSPI_DDR_HHC_ANALOG_DELAY,
        .SIOOMode = QSPI_SIOO_INST_EVERY_CMD,
    };
    
    _QSPI.write(cmd, data, len);
}








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


[[gnu::section(".stack.main")]] uint8_t _StackMain[1024];
asm(".global _StackMainEnd");
asm(".equ _StackMainEnd, _StackMain+1024");



int main() {
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
    
    _QSPI.init();
    
    // Send 8 clocks and wait for them to complete
    alignas(64) static const uint32_t ff = 0xffffffff;
    _ice_qspiWrite(&ff, 4);
    
    for (;;);
    return 0;
}
