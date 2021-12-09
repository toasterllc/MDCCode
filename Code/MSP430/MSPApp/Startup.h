#pragma once
#include <msp430.h>

class Startup {
public:
    static bool ColdStart() {
        return !(PMMIFG & PMMLPM5IFG);
    }
    
private:
    // _startup() is called before main() via the crt machinery, because it's placed in
    // a .crt_NNNN_xxx section. The NNNN part of the section name defines the order that
    // this function is called relative to the other crt functions.
    //
    // We chose 0401 because 0400 is the `move_highdata` crt function (which copies data
    // into memory), while 0500 is the `run_preinit_array` crt function (which
    // calls C++ constructors). We need the correct values stored in BAKMEM after other
    // data is copied into memory, but before C++ constructors are called, so 0401 makes
    // sense.
    //
    // See the `crt0.S` file in the newlib project for more info.
    __attribute__((section(".crt_0401_startup"), naked, used))
    static void _startup() {
        extern uint8_t _ram_backup_src[];
        extern uint8_t _ram_backup_dststart[];
        extern uint8_t _ram_backup_dstend[];
        memcpy(_ram_backup_dststart, _ram_backup_src, _ram_backup_dstend-_ram_backup_dststart);
    }
};
