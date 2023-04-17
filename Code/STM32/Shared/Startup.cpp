#include <string.h>
#include "stm32f7xx.h"

#warning TODO: if RAM gets tight, STMApp and STMLoader could share the same stacks (such as _StackInterrupt and the task stacks) instead of having their own stacks

extern "C" void __libc_init_array();

// √ rename Startup -> _Startup to match MSP
// - define _Stack the same way we do with MSPApp (use _TaskCmdRecv's stack)
// - _PSPStackActivate(): set PSP to _Stack
// - update large comment below since it's no longer true that interrupts need to be disabled
//   after we start using _TaskCmdRecv's stack. however we should keep interrupts disabled
//   while performing this bootstrapping functions, as it's just good practice.
// - compare st library directories between STLoader and STApp

[[gnu::always_inline]]
static inline void _StackInit() {
    // Set the MSP+PSP stack pointers
    // Hardware typically initializes MSP to the SP value at the start of the vector table, but we
    // still need to set MSP here (in addition to PSP) because in the STMApp case, we're executing
    // because the bootloader invoked our ISR_Reset() directly (not via hardware). Therefore in
    // that case, hardware didn't initialize MSP, so we need to initialize it manually here.
    asm volatile("ldr r0, =_StartupStackInterrupt" : : : ); // r0  = _StackInterrupt
    asm volatile("msr msp, r0" : : : );                     // msp = r0
    asm volatile("ldr r0, =_StartupStack" : : : );          // r0  = _Stack
    asm volatile("msr psp, r0" : : : );                     // psp = r0
    
    // Make PSP the active stack
    asm volatile("mrs r0, CONTROL" : : : );             // r0 = CONTROL
    asm volatile("orrs r0, r0, #2" : : : );             // Set SPSEL bit (enable using PSP stack)
    asm volatile("msr CONTROL, r0" : : : );             // CONTROL = r0
    asm volatile("isb" : : : );                         // Instruction Synchronization Barrier
}

// Startup() needs to be in the .isr section so that it's near ISR_Reset,
// otherwise we can get a linker error.
extern "C"
[[noreturn, gnu::naked, gnu::section(".isr")]]
void _Startup() {
    extern uint8_t _sdata_flash[];
    extern uint8_t _sdata_ram[];
    extern uint8_t _edata_ram[];
    extern uint8_t _sbss[];
    extern uint8_t _ebss[];
    extern uint8_t VectorTable[];
    
    // Disable interrupts so that they don't occur until we enter our first Scheduler task.
    __disable_irq();
    
    // Initialize our stack
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
