#pragma once
#include "Enum.h"

namespace STApp {
    Enum(uint8_t, Endpoint, Endpoints,
        Control = 0x00,
        // OUT endpoints (high bit 0)
        CmdOut  = 0x01,
        // IN endpoints (high bit 1)
        CmdIn   = 0x81,
        PixIn   = 0x82,
    );
    
    Enum(uint8_t, EndpointIdx, EndpointIdxs,
        Control = 0x00,
        CmdOut  = 0x01,
        CmdIn   = 0x02,
        PixIn   = 0x03,
    );
    
    // Vendor-defined Control Requests
    Enum(uint8_t, CtrlReq, CtrlReqs,
        Reset,
    );
    
    struct Cmd {
        enum class Op : uint8_t {
            PixGetStatus,
            PixReset,
            PixI2CTransaction,
            PixCapture,
            LEDSet,
        };
        
        Op op;
        union {
            struct __attribute__((packed)) {
            } pixGetStatus;
            
            struct __attribute__((packed)) {
            } pixReset;
            
            struct __attribute__((packed)) {
                uint8_t write;
                uint16_t addr;
                uint16_t val;
            } pixI2CTransaction;
            
            struct __attribute__((packed)) {
            } pixCapture;
            
            struct __attribute__((packed)) {
                uint8_t idx;
                uint8_t on;
            } ledSet;
        } arg;
        
    } __attribute__((packed));
    static_assert(sizeof(Cmd)==6, "Cmd: invalid size");
    
    enum class PixState : uint8_t {
        Idle,
        Capturing,
        Error,
    };
    
    struct PixStatus {
        PixState state = PixState::Idle;
        uint8_t i2cErr = 0;
        uint16_t i2cReadVal = 0;
    } __attribute__((packed));
    
    struct PixHeader {
        uint16_t width = 0;
        uint16_t height = 0;
        uint32_t highlightCount = 0;
        uint32_t shadowCount = 0;
    } __attribute__((packed));
    
    using Pixel = uint16_t;
}
