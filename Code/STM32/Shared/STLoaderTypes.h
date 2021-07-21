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
        MSPDisconnect,
        MSPRead,
        MSPWrite,
        MSPDebug,
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
                uint32_t writeLen;
                uint32_t readLen;
            } MSPDebug;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==9, "Cmd: invalid size");
    
    Enum(uint8_t, MSPDebugCmd, MSPDebugCmds,
        TestOut0,
        TestOut1,
        TestIn,
        RstOut0,
        RstOut1,
        RstIn,
        RstRead,
        Flush,
    );
    
//    struct MSPDebugCmd {
//        Enum(uint8_t, Pin, Pins,
//            Test,
//            Rst,
//        );
//        
//        Enum(uint8_t, Op, Ops,
//            Out0,
//            Out1,
//            In,
//            Read,
//        );
//        
//        MSPDebugCmd(Pin pin, Op op) {
//            opSet(Ops::SetPins);
//            testPinStateSet(test);
//            rstPinStateSet(rst);
//        }
//        
//        Pin pinGet() const      { return (data&(0x01<<0))>>0;           }
//        void pinSet(Pin x)      { data = (data&(~(0x01<<0)))|(x<<0);    }
//        
//        Op opGet() const        { return (data&(0x03<<1))>>1;           }
//        void opSet(Op x)        { data = (data&(~(0x03<<1)))|(s<<1);    }
//        
//        uint8_t data = 0;
//    } __attribute__((packed));
    
    
//    struct MSPDebugCmd {
//        Enum(uint8_t, Pin, Pins,
//            Test,
//            Rst,
//        );
//        
//        Enum(uint8_t, Op, Ops,
//            Out0,
//            Out1,
//            In,
//            Read,
//        );
//        
//        MSPDebugCmd(Pin pin, Op op) {
//            opSet(Ops::SetPins);
//            testPinStateSet(test);
//            rstPinStateSet(rst);
//        }
//        
//        Pin pinGet() const      { return (data&(0x01<<0))>>0;           }
//        void pinSet(Pin x)      { data = (data&(~(0x01<<0)))|(x<<0);    }
//        
//        Op opGet() const        { return (data&(0x03<<1))>>1;           }
//        void opSet(Op x)        { data = (data&(~(0x03<<1)))|(s<<1);    }
//        
//        uint8_t data = 0;
//    } __attribute__((packed));
}
