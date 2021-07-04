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
        DataIn      = 0x81,
    );
    
    Enum(uint8_t, EndpointIdx, EndpointIdxs,
        CmdOut = 1,
        DataOut,
        DataIn,
    );
    
    enum class Op : uint8_t {
        None,
        // STM32 Bootloader
        STWrite,
        STReset,
        // ICE40 Bootloader
        ICEWrite,
        // MSP430 Bootloader
        MSPConnect,
        MSPRead,
        MSPWrite,
        MSPReadRegs,
        MSPWriteRegs,
        MSPDisconnect,
        // Other commands
        LEDSet,
    };
    
    enum class Status : uint8_t {
        OK,
        Busy,
        Error
    };
    
    struct Cmd {
        Op op;
        union {
            struct {
                uint32_t addr;
                uint32_t len;
            } STWrite;
            
            struct {
                uint32_t entryPointAddr;
            } STReset;
            
            struct {
                uint32_t len;
            } ICEWrite;
            
            struct {
                uint32_t addr;
                uint32_t len;
            } MSPRead;
            
            struct {
                uint32_t addr;
                uint32_t len;
            } MSPWrite;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==9, "Cmd: invalid size");
}
