#pragma once
#include "Enum.h"

namespace STLoader {
    Enum(uint8_t, InterfaceIdx, InterfaceIdxs,
        STM32,
        ICE40,
        MSP430,
    );
    
    Enum(uint8_t, Endpoint, Endpoints,
        // OUT endpoints (high bit 0)
        Ctrl            = 0x00,
        
        // OUT endpoints (high bit 0)
        STCmdOut        = 0x01,
        STDataOut       = 0x02,
        ICECmdOut       = 0x03,
        ICEDataOut      = 0x04,
        MSPCmdOut       = 0x05,
        MSPDataOut      = 0x06,
        
        // IN endpoints (high bit 1)
        STStatusIn      = 0x81,
        ICEStatusIn     = 0x82,
        MSPStatusIn     = 0x82,
    );
    
    Enum(uint8_t, EndpointIdx, EndpointIdxs,
        STCmdOut = 1,
        STDataOut,
        STStatusIn,
        
        ICECmdOut = 1,
        ICEDataOut,
        ICEStatusIn,
    );
    
    struct STCmd {
        enum class Op : uint8_t {
            GetStatus,
            WriteData,
            Reset,
            LEDSet,
        };
        
        Op op;
        union {
            struct {
                uint8_t idx;
                uint8_t on;
            } ledSet;
            
            struct {
                uint32_t addr;
            } writeData;
            
            struct {
                uint32_t entryPointAddr;
            } reset;
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
    
    enum class ICEStatus : uint8_t {
        Idle,
        Configuring,
        Done,
        Error
    };
}
