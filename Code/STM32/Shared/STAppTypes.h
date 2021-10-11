#pragma once
#include "Toastbox/Enum.h"

namespace STApp {
    Enum(uint8_t, Endpoint, Endpoints,
        // Control endpoint
        Ctrl    = 0x00,
        // IN endpoints (high bit 1)
        DataIn  = 0x81,
    );
    
    enum class Op : uint8_t {
        None,
        Reset,
        Bootloader,
        SDRead,
        ImgReset,
        ImgI2C,
        ImgCapture,
        LEDSet,
    };
    
    struct Cmd {
        Op op;
        union {
            struct __attribute__((packed)) {
                uint32_t addr;
            } SDRead;
            
            struct __attribute__((packed)) {
                uint8_t write;
                uint8_t _pad;
                uint16_t addr;
                uint16_t val;
            } ImgI2C;
            
            struct __attribute__((packed)) {
            } ImgCapture;
            
            struct __attribute__((packed)) {
                uint8_t idx;
                uint8_t on;
            } LEDSet;
        } arg;
        
    } __attribute__((packed));
    static_assert(sizeof(Cmd)<=64, "Cmd: invalid size"); // Verify that Cmd will fit in a single EP0 packet
    
    struct ImgCaptureStatus {
        uint8_t ok;
        uint8_t _pad[3];
        uint32_t wordCount;
        uint32_t highlightCount;
        uint32_t shadowCount;
    } __attribute__((packed));
    
    struct ImgI2CStatus {
        uint8_t ok;
        uint8_t _pad;
        uint16_t readData;
    } __attribute__((packed));
}
