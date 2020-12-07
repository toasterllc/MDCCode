#pragma once

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
            GetPixInfo,
            PixStream,
            LEDSet,
        };
        
        Op op;
        union {
            struct {
            } getPixInfo;
            
            struct {
                bool test;
            } pixStream;
            
            struct {
                uint8_t idx;
                uint8_t on;
            } ledSet;
        } arg;
        
    } __attribute__((packed));
    
    struct PixInfo {
        uint16_t width;
        uint16_t height;
    } __attribute__((packed));
    
    using Pixel = uint16_t;
    
    static_assert(sizeof(Cmd)==3, "Cmd: invalid size");
}
