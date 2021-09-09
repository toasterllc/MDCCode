#pragma once
#include "Toastbox/Enum.h"

namespace STApp {
    Enum(uint8_t, Endpoint, Endpoints,
        // Control endpoint
        Ctrl    = 0x00,
        // IN endpoints (high bit 1)
        DataIn  = 0x81,
    );
    
    // Vendor-defined Control Requests
    Enum(uint8_t, CtrlReq, CtrlReqs,
        CmdExec,
    );
    
    enum class Status : uint8_t {
        OK,
        Busy,
        Error
    };
    
    enum class Op : uint8_t {
        None,
        SDRead,
        LEDSet,
    };
    
    struct Cmd {
        Op op;
        union {
            struct __attribute__((packed)) {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
        } arg;
        
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==3, "Cmd: invalid size");
}
