#include <string.h>
#include "stm32f7xx.h"

extern "C" void __libc_init_array();

#warning TODO: confirm that at the point of executing `mrs r0, msp`, SP=_StackInterruptEnd
[[gnu::always_inline]]
static inline void _PSPStackActivate() {
    // Switch to using PSP stack.
    // Scheduler and its tasks use the PSP stack, while interrupts are handled on the MSP stack.
    asm volatile("mrs r0, msp" : : : );         // r0 = msp
    asm volatile("msr psp, r0" : : : );         // psp = r0
    asm volatile("mrs r0, CONTROL" : : : );     // r0 = CONTROL
    asm volatile("orrs r0, r0, #2" : : : );     // Set SPSEL bit (enable using PSP stack)
    asm volatile("msr CONTROL, r0" : : : );     // CONTROL = r0
    asm volatile("isb" : : : );                 // Instruction Synchronization Barrier
}

// Startup() needs to be in the .isr section so that it's near ISR_Reset,
// otherwise we can get a linker error.
extern "C" [[gnu::section(".isr")]]
void Startup() {
    extern uint8_t _sdata_flash[];
    extern uint8_t _sdata_ram[];
    extern uint8_t _edata_ram[];
    extern uint8_t _sbss[];
    extern uint8_t _ebss[];
    extern uint8_t VectorTable[];
    
    // Disable interrupts so that they don't occur until Scheduler explicitly enables them.
    //
    // Disabling interrupts is necessary because _PSPStackActivate() sets the PSP stack
    // to the same region as the MSP stack, and then activates the PSP stack. (We want
    // to activate the PSP stack so that Scheduler and our tasks all execute using the
    // PSP stack, and only interrupt handling executes using the MSP stack.) Therefore
    // if an interrupt occurred after calling _PSPStackActivate(), the interrupt would
    // be serviced using the MSP stack and would clobber the PSP stack since they
    // share the same region of memory, so we disable interrupts to prevent this
    // clobbering.
    //
    // Scheduler enables interrupts only after setting the stack pointer (ie PSP) to
    // the first task's stack, which is safe at that point because PSP and MSP no
    // longer share the same memory region.
    __disable_irq();
    
    // Switch from MSP stack -> PSP stack
    _PSPStackActivate();
    
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
