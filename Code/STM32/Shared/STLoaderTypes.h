#pragma once
#include "Toastbox/Enum.h"

namespace STLoader {
    Enum(uint8_t, Endpoint, Endpoints,
        // Control endpoint
        Ctrl    = 0x00,
        // OUT endpoints (high bit 0)
        DataOut = 0x01,
        // IN endpoints (high bit 1)
        DataIn  = 0x81,
    );
    
    // Vendor-defined Control Requests
    Enum(uint8_t, CtrlReq, CtrlReqs,
        CmdExec,
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
            struct __attribute__((packed)) {
                uint32_t addr;
                uint32_t len;
            } STWrite;
            
            struct __attribute__((packed)) {
                uint32_t entryPointAddr;
            } STReset;
            
            struct __attribute__((packed)) {
                uint32_t len;
            } ICEWrite;
            
            struct __attribute__((packed)) {
                uint32_t addr;
                uint32_t len;
            } MSPRead;
            
            struct __attribute__((packed)) {
                uint32_t addr;
                uint32_t len;
            } MSPWrite;
            
            struct __attribute__((packed)) {
                uint32_t writeLen;
                uint32_t readLen;
            } MSPDebug;
            
            struct __attribute__((packed)) {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==9, "Cmd: invalid size");
    
    struct MSPDebugCmd {
        Enum(uint8_t, Op, Ops,
            TestSet,
            RstSet,
            TestPulse,
            SBWIO,
        );
        
        struct TestSetType {}; static constexpr auto TestSet = TestSetType();
        struct RstSetType {}; static constexpr auto RstSet = RstSetType();
        struct TestPulseType {}; static constexpr auto TestPulse = TestPulseType();
        struct SBWIOType {}; static constexpr auto SBWIO = SBWIOType();
        
        MSPDebugCmd(TestSetType, bool val) {
            opSet(Ops::TestSet);
            pinValSet(val);
        }
        
        MSPDebugCmd(RstSetType, bool val) {
            opSet(Ops::RstSet);
            pinValSet(val);
        }
        
        MSPDebugCmd(TestPulseType) {
            opSet(Ops::TestPulse);
        }
        
        MSPDebugCmd(SBWIOType, bool tms, bool tclk, bool tdi, bool tdoRead) {
            opSet(Ops::SBWIO);
            tmsSet(tms);
            tclkSet(tclk);
            tdiSet(tdi);
            tdoReadSet(tdoRead);
        }
        
        Op opGet() const            { return (data&(0x03<<0))>>0; }
        void opSet(Op x)            { data = (data&(~(0x03<<0)))|(x<<0); }
        
        bool pinValGet() const      { return (data&(0x01<<2))>>2; }
        void pinValSet(bool x)      { data = (data&(~(0x01<<2)))|(x<<2); }
        
        bool tmsGet() const         { return (data&(0x01<<2))>>2; }
        void tmsSet(bool x)         { data = (data&(~(0x01<<2)))|(x<<2); }
        
        bool tclkGet() const        { return (data&(0x01<<3))>>3; }
        void tclkSet(bool x)        { data = (data&(~(0x01<<3)))|(x<<3); }
        
        bool tdiGet() const         { return (data&(0x01<<4))>>4; }
        void tdiSet(bool x)         { data = (data&(~(0x01<<4)))|(x<<4); }
        
        bool tdoReadGet() const     { return (data&(0x01<<5))>>5; }
        void tdoReadSet(bool x)     { data = (data&(~(0x01<<5)))|(x<<5); }
        
        uint8_t data = 0;
    } __attribute__((packed));
}
