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
    
    struct Cmd {
        enum class Op : uint8_t {
            StatusGet,
            
            STWrite,
            STReset
            
            ICEStart,
            ICEFinish
            
            MSPStart,
            MSPFinish,
            
            LEDSet,
        };
        
        Op op;
        union {
            struct {
                uint32_t addr;
            } STWrite;
            
            struct {
                uint32_t entryPointAddr;
            } STReset;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(STCmd)==5, "STCmd: invalid size");
    
    enum class STStatus : uint8_t {
        Idle,
        Writing,
    };
    
    struct ICECmd {
        enum class Op : uint8_t {
            GetStatus,
            Start,
            Finish
        };
        
        Op op;
        union {
            struct {
                uint32_t len;
            } start;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(ICECmd)==5, "ICECmd: invalid size");
    
    enum class Status : uint8_t {
        Idle,
        Underway,
        Done,
        Error
    };
}
