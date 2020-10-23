#pragma once

struct STLoaderCmd {
    enum class Op : uint8_t {
        None,
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
static_assert(sizeof(STLoaderCmd)==5, "STLoaderCmd: invalid size");

enum class STLoaderStatus : uint8_t {
    Idle,
    Writing,
};

struct ICELoaderCmd {
    enum class Op : uint8_t {
        None,
        Start,
        Stop,
        WriteData,
    };
    
    Op op;
//    union {
//        struct {
//        } start;
//        
//        struct {
//        } stop;
//        
//        struct {
//        } writeData;
//    } arg;
} __attribute__((packed));
static_assert(sizeof(ICELoaderCmd)==1, "ICELoaderCmd: invalid size");
