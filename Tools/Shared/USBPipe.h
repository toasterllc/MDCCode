#pragma once
#include <IOKit/IOKitLib.h>
#include "USBInterface.h"

class USBPipe {
public:
    // Default constructor: empty
    USBPipe() {}
    
    USBPipe(USBInterface& interface, uint8_t idx) : _interface(interface), _idx(idx) {}
    
    operator bool() const { return _interface; }
    
    template <typename T>
    IOReturn write(T& x) const {
        return (*_interface.interface())->WritePipe(_interface.interface(), _idx, (void*)&x, sizeof(x));
    }
    
    IOReturn write(const void* buf, size_t len) const {
        return (*_interface.interface())->WritePipe(_interface.interface(), _idx, (void*)buf, (uint32_t)len);
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
    IOReturn read(T& t) const {
        uint32_t len32 = (uint32_t)sizeof(t);
        IOReturn ior = (*_interface.interface())->ReadPipe(_interface.interface(), _idx, &t, &len32);
        if (ior != kIOReturnSuccess) return ior;
        if (len32 < sizeof(t)) return kIOReturnUnderrun;
        return kIOReturnSuccess;
    }
    
    IOReturn read(void* buf, size_t len) const {
        uint32_t len32 = (uint32_t)len;
        IOReturn ior = (*_interface.interface())->ReadPipe(_interface.interface(), _idx, buf, &len32);
        if (ior != kIOReturnSuccess) return ior;
        if (len32 < len) return kIOReturnUnderrun;
        return kIOReturnSuccess;
    }
    
    IOReturn reset() const {
        return (*_interface.interface())->ResetPipe(_interface.interface(), _idx);
    }
    
private:
    USBInterface _interface;
    uint8_t _idx = 0;
};
