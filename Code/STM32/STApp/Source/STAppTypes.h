#pragma once

namespace STApp {
    struct Cmd {
        enum class Op : uint8_t {
            PixStreamReset,
            PixStreamStart,
            LEDSet,
        };
        
        Op op;
        union {
            struct {
            } pixStreamReset;
            
            struct {
            } pixStreamStart;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } ledSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==3, "Cmd: invalid size");
}
