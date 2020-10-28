#include "StartupBase.h"
#include <string.h>
#include "stm32f7xx.h"

extern "C" void __libc_init_array();

void StartupBase::runInit() {
}

void StartupBase::run() {
    extern uint8_t _sidata[];
    extern uint8_t _sdata[];
    extern uint8_t _edata[];
    extern uint8_t _sbss[];
    extern uint8_t _ebss[];
    extern uint8_t _sisr_vector[];
    extern int main() __attribute__((noreturn));
    
    runInit();
    
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
