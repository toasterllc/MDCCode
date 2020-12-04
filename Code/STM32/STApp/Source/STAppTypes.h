#pragma once

namespace STApp {
    struct Cmd {
        enum class Op : uint8_t {
            PixStream,
            LEDSet,
        };
        
        Op op;
        union {
            struct {
                uint8_t enable;
            } pixStream;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } ledSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==3, "Cmd: invalid size");
}
