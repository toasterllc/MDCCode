#pragma once
#include <msp430.h>
#include <cstring>

extern "C" void __libc_init_array();

class Startup {
public:
    static uint16_t ResetReason() {
        static uint16_t X = SYSRSTIV;
        return X;
    }
    
    // ColdStart() truth table:
    //
    //   Initial power on:    true
    //   Wake from LPM4.5:    false *
    //   Wake from LPM3.5:    false
    //   Startup after abort: false
    //
    //   * Ideally this case would return true because LPM4.5 is essentially 'off'
    //     (it only retains IO pin states). But when waking there doesn't appear
    //     to be a way to differentitate between waking from LPM3.5 vs LPM4.5,
    //     so there doesn't seem to be a way to return true in the LPM4.5 case.
    //     We don't use LPM4.5 though so it's not an issue.
    static bool ColdStart() {
        return (ResetReason()==SYSRSTIV_NONE || ResetReason()==SYSRSTIV_BOR);
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
        asm volatile("mov #_StartupStack, sp" : : : );
    } else {
        // Large memory model
        asm volatile("mov.a #_StartupStack, sp" : : : );
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

// u16 because reset vectors must be 16-bit, even in large memory model mode where pointers
// are 20-bit (stored as u32)
[[gnu::section(".resetvec"), gnu::used]]
uint16_t _ResetVector[] = {
    (uint16_t)(uintptr_t)&_Startup,
};
