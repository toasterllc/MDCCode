#pragma once

namespace STLoader {
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
            Finish,
            ReadCDONE,
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
    };
    
    enum class ICECDONE : uint8_t {
        Error,
        OK,
    };
}
