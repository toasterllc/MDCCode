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

[[noreturn]]
[[gnu::naked]] // No function preamble because we always abort, so we don't need to preserve any registers
void _ISR_RESET() {
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
    
    // Disable watchdog since we don't know how long our startup code takes
    WDTCTL = WDTPW | WDTHOLD;
    
    // Copy .data section from flash to RAM
    memcpy(_sdata_ram, _sdata_flash, _edata_ram-_sdata_ram);
    
    // Zero .bss section
    memset(_sbss, 0, _ebss-_sbss);
    
    // Zero the .ram_backup_bss section if this is a cold start.
    // Otherwise, BAKMEM content should remain untouched, because it's
    // supposed to persist during sleep.
    if (Startup::ColdStart()) {
        extern uint8_t _ram_backup_bss_start[];
        extern uint8_t _ram_backup_bss_end[];
        memset(_ram_backup_bss_start, 0, _ram_backup_bss_end-_ram_backup_bss_start);
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
