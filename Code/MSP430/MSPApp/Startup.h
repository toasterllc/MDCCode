#pragma once
#include <msp430.h>
#include <cstring>

extern "C" void __libc_init_array();

class Startup {
public:
    // Initial power on:    true
    // Wake from LPM4.5:    true
    // Wake from LPM3.5:    false
    // Startup after abort: false
    static bool ColdStart() {
        // This is a cold start if we're not waking from LPM3.5
        static bool coldStart = (SYSRSTIV != SYSRSTIV_LPM5WU);
        return coldStart;
    }
};

extern "C"
[[noreturn, gnu::naked]]
void _Startup() {
    extern uint8_t _sdata_flash[];
    extern uint8_t _sdata_ram[];
    extern uint8_t _edata_ram[];
    extern uint8_t _sbss[];
    extern uint8_t _ebss[];
    
    // Load stack pointer
    if constexpr (sizeof(void*) == 2) {
        // Small memory model
        asm("mov #_StartupStack, sp");
    } else {
        // Large memory model
        asm("mov.a #_StartupStack, sp");
    }
    
    // Copy .data section from flash to RAM
    memcpy(_sdata_ram, _sdata_flash, _edata_ram-_sdata_ram);
    
    // Zero .bss section
    memset(_sbss, 0, _ebss-_sbss);
    
    // Only copy the data from FRAM -> BAKMEM if this is a cold start.
    // Otherwise, BAKMEM content should remain untouched, because it's
    // supposed to persist during sleep.
    if (Startup::ColdStart()) {
        extern uint8_t _ram_backup_src[];
        extern uint8_t _ram_backup_dststart[];
        extern uint8_t _ram_backup_dstend[];
        memcpy(_ram_backup_dststart, _ram_backup_src, _ram_backup_dstend-_ram_backup_dststart);
    }
    
    // Call static constructors
    __libc_init_array();
    
    // Call main function
    [[noreturn]] extern int main();
    main();
}

// _init(): required by __libc_init_array
extern "C"
void _init() {}

[[gnu::section(".resetvec"), gnu::used]]
void* _ResetVector[] = {
    (void*)&_Startup,
};
