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
            Stop,
            WriteData,
        };
        
        Op op;
        union {
            struct {
            } start;
            
            struct {
            } stop;
            
            struct {
            } writeData;
        } arg;
    } __attribute__((packed));
    static_assert(sizeof(ICECmd)==2, "ICECmd: invalid size");
    
    enum class ICEStatus : uint8_t {
        Idle,
        Writing,
    };
}
