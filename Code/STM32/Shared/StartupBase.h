#pragma once
#include <string.h>
#include "stm32f7xx.h"

extern "C" void __libc_init_array();

template <typename T>
class StartupBase {
public:
    void run() {
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
        SCB->VTOR = (uint32_t)VectorTable;
        
        // Call static constructors
        __libc_init_array();
        
        // Call main function
        main();
        
        // Loop forever if main returns
        for (;;);
    }
};

// `StartupRun` is called by VectorTable.s, and must be provided by the client
extern "C" void StartupRun();
