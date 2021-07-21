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
    
    struct MSPDebugCmd {
        Enum(uint8_t, Op, Ops,
            SetPins,
            SBWIO,
        );
        
        Enum(uint8_t, PinState, PinStates,
            Out0,
            Out1,
            In,
            Pulse01,
        );
        
        MSPDebugCmd(PinState test, PinState rst) {
            opSet(Ops::SetPins);
            testPinStateSet(test);
            rstPinStateSet(rst);
        }
        
        MSPDebugCmd(bool tms, bool tclk, bool tdi, bool tdoRead) {
            opSet(Ops::SBWIO);
            tmsSet(tms);
            tclkSet(tclk);
            tdiSet(tdi);
            tdoReadSet(tdoRead);
        }
        
        Op opGet() const                    { return (data&(1<<7))>>7; }
        void opSet(Op op)                   { data = (data&(~(1<<7)))|(op<<7); }
        
        PinState testPinStateGet() const    { return (data&(0x03<<2))>>2; }
        void testPinStateSet(PinState s)    { data = (data&(~(0x03<<2)))|(s<<2); }
        
        PinState rstPinStateGet() const     { return (data&(0x03<<0))>>0; }
        void rstPinStateSet(PinState s)     { data = (data&(~(0x03<<0)))|(s<<0); }
        
        bool tmsGet() const     { return (data&(1<<3))>>3; }
        void tmsSet(bool s)     { data = (data&(~(1<<3)))|(s<<3); }
        
        bool tclkGet() const    { return (data&(1<<2))>>2; }
        void tclkSet(bool s)    { data = (data&(~(1<<2)))|(s<<2); }
        
        bool tdiGet() const     { return (data&(1<<1))>>1; }
        void tdiSet(bool s)     { data = (data&(~(1<<1)))|(s<<1); }
        
        bool tdoReadGet() const { return (data&(1<<0))>>0; }
        void tdoReadSet(bool s) { data = (data&(~(1<<0)))|(s<<0); }
        
        uint8_t data = 0;
    } __attribute__((packed));
}
