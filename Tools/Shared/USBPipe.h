#pragma once
#include <IOKit/IOKitLib.h>
#include "USBInterface.h"
#include "RuntimeError.h"

class USBPipe {
public:
    // Default constructor: empty
    USBPipe() {}
    
    USBPipe(USBInterface& interface, uint8_t idx) : _interface(interface), _idx(idx) {}
    
    operator bool() const { return _interface; }
    
    template <typename T>
    void write(T& x) const {
        IOReturn ior = (*_interface.interface())->WritePipe(_interface.interface(), _idx, (void*)&x, sizeof(x));
        if (ior != kIOReturnSuccess) throw RuntimeError("WritePipe() failed: %x", ior);
    }
    
    void write(const void* buf, size_t len) const {
        IOReturn ior = (*_interface.interface())->WritePipe(_interface.interface(), _idx, (void*)buf, (uint32_t)len);
        if (ior != kIOReturnSuccess) throw RuntimeError("WritePipe() failed: %x", ior);
    }
    
//    template <typename T>
//    std::tuple<T, IOReturn> read() const {
//        T t;
//        uint32_t len32 = (uint32_t)sizeof(t);
//        IOReturn ior = (*_interface.interface())->ReadPipe(_interface.interface(), _idx, &t, &len32);
//        if (ior != kIOReturnSuccess) return std::make_tuple(t, ior);
//        if (len32 < sizeof(t)) return std::make_tuple(t, kIOReturnUnderrun);
//        return std::make_tuple(t, ior);
//    }
    
    template <typename T>
    void read(T& t) const {
        uint32_t len32 = (uint32_t)sizeof(t);
        IOReturn ior = (*_interface.interface())->ReadPipe(_interface.interface(), _idx, &t, &len32);
        if (ior != kIOReturnSuccess) throw RuntimeError("ReadPipe() failed: %x", ior);
        if (len32 != sizeof(t)) throw RuntimeError("ReadPipe() returned bad length; expected %ju bytes, got %ju bytes",
            (uintmax_t)sizeof(t), (uintmax_t)len32);
    }
    
    void read(void* buf, size_t len) const {
        uint32_t len32 = (uint32_t)len;
        IOReturn ior = (*_interface.interface())->ReadPipe(_interface.interface(), _idx, buf, &len32);
        if (ior != kIOReturnSuccess) throw RuntimeError("ReadPipe() failed: %x", ior);
        if (len32 != len) throw RuntimeError("ReadPipe() returned bad length; expected %ju bytes, got %ju bytes",
            (uintmax_t)len, (uintmax_t)len32);
    }
    
    void reset() const {
        IOReturn ior = (*_interface.interface())->ResetPipe(_interface.interface(), _idx);
        if (ior != kIOReturnSuccess) throw RuntimeError("ResetPipe() failed: %x", ior);
    }
    
private:
    USBInterface _interface;
    uint8_t _idx = 0;
};
