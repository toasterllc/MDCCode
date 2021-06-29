#pragma once
#include "Enum.h"

namespace STLoader {
    Enum(uint8_t, Endpoint, Endpoints,
        // Control endpoint
        Ctrl        = 0x00,
        
        // OUT endpoints (high bit 0)
        CmdOut      = 0x01,
        DataOut     = 0x02,
        
        // IN endpoints (high bit 1)
        StatusIn    = 0x81,
    );
    
    Enum(uint8_t, EndpointIdx, EndpointIdxs,
        CmdOut = 1,
        DataOut,
        StatusIn,
    );
    
    enum class Op : uint8_t {
        None,
        // STM32 Bootloader
        STWrite,
        STReset,
        // ICE40 Bootloader
        ICEWrite,
        // MSP430 Bootloader
        MSPWrite,
        // Other commands
        StatusGet,
        LEDSet,
    };
    
    enum class Status : uint8_t {
        Idle,
        Busy,
        Error
    };
    
    struct Cmd {
        Op op;
        union {
            struct {
                uint32_t addr;
            } STWrite;
            
            struct {
                uint32_t entryPointAddr;
            } STReset;
            
            struct {
                uint32_t addr;
            } MSPWrite;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==5, "Cmd: invalid size");
}
