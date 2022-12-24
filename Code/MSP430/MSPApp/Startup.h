#pragma once
#include <msp430.h>
#include <cstring>
#include "FRAMWriteEn.h"

class Startup {
public:
    static bool ColdStart() {
        // This is a cold start if we're not waking from LPM3.5
        static bool coldStart = (SYSRSTIV != SYSRSTIV_LPM5WU);
        return coldStart;
    }
    
private:
//    static bool _ColdStart() {
//        // We're using this technique so that the first run always triggers _ColdStart()==true,
//        // regardless of the reset cause (SYSRSTIV). We want that behavior so that the first
//        // time we load the program via a debugger, it runs as if it's a cold start, even
//        // though it's actually a warm start.
//        [[gnu::section(".fram_info.startup")]]
//        static bool init = false;
//        
//        FRAMWriteEn writeEn; // Enable FRAM writing
//        bool initPrev = init;
//        init = true;
//        return !initPrev || (SYSRSTIV != SYSRSTIV__LPM5WU);
//    }
    
    // _Startup() is called before main() via the crt machinery, because it's placed in
    // a .crt_NNNN_xxx section. The NNNN part of the section name defines the order that
    // this function is called relative to the other crt functions.
    //
    // We chose 0401 because 0400 is the `move_highdata` crt function (which copies data
    // into memory), while 0500 is the `run_preinit_array` crt function (which
    // calls C++ constructors). We need the correct values stored in BAKMEM after other
    // data is copied into memory, but before C++ constructors are called, so 0401 makes
    // sense. Additionally, because _Startup() relies on ColdStart(), it must come after
    // the init_bss/init_highbss sections (0100/0200), because ColdStart() has a static
    // variable that's initialized upon the first call, which implicitly requires a
    // zeroed variable to track whether it's been initialized.
    //
    // See the `crt0.S` file in the newlib project for more info.
    [[gnu::section(".crt_0401._Startup"), gnu::naked, gnu::used]]
    static void _Startup() {
        // Debug code to signal that _Startup() was called by toggling pin A.E
//        {
//            WDTCTL = WDTPW | WDTHOLD;
//            PM5CTL0 &= ~LOCKLPM5;
//            
//            using DEBUG_OUT = GPIO::PortA::Pin<0xE, GPIO::Option::Output0>;
//            DEBUG_OUT::Init();
//            for (int i=0; i<10; i++) {
//                DEBUG_OUT::Write(0);
//                for (volatile uint16_t i=0; i<10000; i++);
//                DEBUG_OUT::Write(1);
//                for (volatile uint16_t i=0; i<10000; i++);
//            }
//        }
        
        // Only copy the data from FRAM -> BAKMEM if this is a cold start.
        // Otherwise, BAKMEM content should remain untouched, because it's
        // supposed to persist during sleep.
        if (ColdStart()) {
            extern uint8_t _ram_backup_src[];
            extern uint8_t _ram_backup_dststart[];
            extern uint8_t _ram_backup_dstend[];
            memcpy(_ram_backup_dststart, _ram_backup_src, _ram_backup_dstend-_ram_backup_dststart);
        }
    }
};
