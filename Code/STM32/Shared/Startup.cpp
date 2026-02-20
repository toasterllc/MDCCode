#include <string.h>
#include "stm32f7xx.h"

#warning TODO: if RAM gets tight, STMApp and STMLoader could share the same stacks (such as _StackInterrupt and the task stacks) instead of having their own stacks

extern "C" void __libc_init_array();
extern "C" void _StackInit();

// Startup() needs to be in the .isr section so that it's near ISR_Reset,
// otherwise we can get a linker error.
[[noreturn, gnu::always_inline]]
static inline void _Startup() {
    extern uint8_t _sdata_flash[];
    extern uint8_t _sdata_ram[];
    extern uint8_t _edata_ram[];
    extern uint8_t _sbss[];
    extern uint8_t _ebss[];
    extern uint8_t VectorTable[];
    
    // Disable interrupts so that they don't occur until we enter our first Scheduler task.
    __disable_irq();
    
    // Initialize our stack; necessary before we make any (non-inlined) function calls
    _StackInit();
    
    // Copy .data section from flash to RAM
    memcpy(_sdata_ram, _sdata_flash, _edata_ram-_sdata_ram);
    // Zero .bss section
    memset(_sbss, 0, _ebss-_sbss);
    
    // FPU settings
    if (__FPU_PRESENT && __FPU_USED) {
        SCB->CPACR |= ((3UL << 10*2)|(3UL << 11*2));  // Set CP10 and CP11 Full Access
    }
    
    // Set the vector table address
    SCB->VTOR = (uint32_t)VectorTable;
    __DSB();
    
    // Call static constructors
    __libc_init_array();
    
    // Call main function
    [[noreturn]] extern int main();
    main();
}

extern "C" [[noreturn, gnu::naked, gnu::section(".isr")]] void ISR_Reset()      { _Startup(); }
extern "C" [[noreturn, gnu::naked, gnu::section(".isr")]] void ISR_Default()    { Assert(false); }
