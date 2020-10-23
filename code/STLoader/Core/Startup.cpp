#include "stm32f7xx.h"

volatile uintptr_t AppEntryPointAddr __attribute__((section(".noinit")));
extern "C" void __libc_init_array();
void Startup() {
    extern uint8_t _sidata[];
    extern uint8_t _sdata[];
    extern uint8_t _edata[];
    extern uint8_t _sbss[];
    extern uint8_t _ebss[];
    extern uint8_t _sisr_vector[];
    extern int main();
    
    // Stash and reset `AppEntryPointAddr` so that we only attempt to start the app once
    // after each software reset.
    const uintptr_t appEntryPointAddr = AppEntryPointAddr;
    AppEntryPointAddr = 0;
    
    // Cache RCC_CSR since we're about to clear it
    auto csr = READ_REG(RCC->CSR);
    // Clear RCC_CSR by setting the RMVF bit
    SET_BIT(RCC->CSR, RCC_CSR_RMVF);
    // Check if we reset due to a software reset (SFTRSTF), and
    // we have the app's vector table.
    if (READ_BIT(csr, RCC_CSR_SFTRSTF) && appEntryPointAddr) {
        // Start the application
        void (*const appEntryPoint)() = (void (*)())appEntryPointAddr;
        appEntryPoint();
        for (;;); // Loop forever if the app returns
    }
    
    // Copy .data section from flash to RAM
    memcpy(_sdata, _sidata, _edata-_sdata);
    // Zero .bss section
    memset(_sbss, 0, _ebss-_sbss);
    
    // FPU settings
    if (__FPU_PRESENT && __FPU_USED) {
        SCB->CPACR |= ((3UL << 10*2)|(3UL << 11*2));  // Set CP10 and CP11 Full Access
    }
    
    // Set the vector table address
    SCB->VTOR = (uint32_t)_sisr_vector;
    
    // Call static constructors
    __libc_init_array();
    
    // Call main function
    main();
    
    // Loop forever if main returns
    for (;;);
}
