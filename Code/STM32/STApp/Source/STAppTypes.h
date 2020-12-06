#pragma once

namespace STApp {
    // Vendor-defined Control Requests
    Enum(uint8_t, CtrlReq, CtrlReqs,
        Reset,
    );
    
    struct Cmd {
        enum class Op : uint8_t {
            PixStream,
            LEDSet,
        };
        
        Op op;
        union {
            struct {
            } pixStream;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } ledSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==3, "Cmd: invalid size");
}
