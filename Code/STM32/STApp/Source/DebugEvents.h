#pragma once
#include "Toastbox/RingBuffer.h"

struct DebugEvent {
#define USBx_BASE 0x40040000
    
    DebugEvent() {}
    
    DebugEvent(char t) :
    type(t),
    DIEPTSIZ0(USBx_INEP(0)->DIEPTSIZ),
    DIEPCTL0(USBx_INEP(0)->DIEPCTL), 
    DIEPDMA0(USBx_INEP(0)->DIEPDMA) {}
    
    char type           = 0x42;
    uint32_t DIEPTSIZ0  = 0x42;
    uint32_t DIEPCTL0   = 0x42;
    uint32_t DIEPDMA0   = 0x42;
    
#undef USBx_BASE
};

inline RingBuffer<DebugEvent,64> DebugEvents;
