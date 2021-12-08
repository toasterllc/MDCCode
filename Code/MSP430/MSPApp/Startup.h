#pragma once
#include <msp430.h>

class Startup {
public:
    static bool ColdStart() { return _ColdStart; }
    
private:
    static inline bool _ColdStart = false;
    
    // _startup() is called before main() via the crt machinery, because it's placed in
    // a .crt_NNNN_xxx section. The NNNN part of the section name defines the order that
    // this function is called relative to the other crt functions.
    //
    // We chose 0401 because 0400 is the `move_highdata` crt function (which copies data
    // into memory), while 0500 is the `run_preinit_array` crt function (which
    // calls C++ constructors). We need the correct values stored in BAKMEM before C++
    // constructors are called, but after other data is copied, so 0401 makes sense.
    ///
    // See the `crt0.S` file in the newlib project for more info.
    __attribute__((section(".crt_0401_startup"), naked, used))
    static void _startup() {
        _ColdStart = (SYSRSTIV != SYSRSTIV_LPM5WU);
        
        // Only copy the data into BAKMEM if this is a cold start
        if (_ColdStart) {
            extern uint8_t _sbakmem_fram[];
            extern uint8_t _sbakmem_ram[];
            extern uint8_t _ebakmem_ram[];
            memcpy(_sbakmem_ram, _sbakmem_fram, _ebakmem_ram-_sbakmem_ram);
        }
    }
};
