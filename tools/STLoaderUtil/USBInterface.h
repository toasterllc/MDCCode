#pragma once
#include <IOKit/IOKitLib.h>

class USBInterface {
public:
    // Default constructor: empty
    USBInterface() {}
    
    // Constructor: take ownership of a IOUSBInterfaceInterface
    USBInterface(IOUSBInterfaceInterface** interface) {
        set(interface);
    }
    
    // Copy constructor: illegal
    USBInterface(const USBInterface&) = delete;
    // Move constructor: use move assignment operator
    USBInterface(USBInterface&& x) { *this = std::move(x); }
    // Move assignment operator
    USBInterface& operator=(USBInterface&& x) {
        // Retain the interface on behalf of `set`
        auto interface = x._interface;
        if (interface) (*interface)->AddRef(interface);
        
        x.set(nullptr); // Reset x's interface first, so that it calls USBInterfaceClose before we call USBInterfaceOpen
        set(interface);
        return *this;
    }
    
    ~USBInterface() {
        set(nullptr);
    }
    
    IOUSBInterfaceInterface** interface() {
        assert(_interface);
        return _interface;
    }
    
    operator bool() const { return _interface; }
    
    IOReturn write(uint8_t pipe, const void* buf, size_t len) {
        assert(_interface);
        _openIfNeeded();
        return (*_interface)->WritePipe(_interface, pipe, (void*)buf, (uint32_t)len);
    }
    
    std::tuple<size_t, IOReturn> read(uint8_t pipe, void* buf, size_t len) {
        assert(_interface);
        _openIfNeeded();
        uint32_t len32 = (uint32_t)len;
        IOReturn ior = (*_interface)->ReadPipe(_interface, pipe, buf, &len32);
        return std::make_tuple(len32, ior);
    }
    
    // Take ownership of a IOUSBInterfaceInterface
    void set(IOUSBInterfaceInterface** interface) {
        if (_interface) {
            if (_open) (*_interface)->USBInterfaceClose(_interface);
            (*_interface)->Release(_interface);
        }
        
        _interface = interface;
        _open = false;
    }
    
private:
    void _openIfNeeded() {
        if (!_open) {
            (*_interface)->USBInterfaceOpen(_interface);
            _open = true;
        }
    }
    
    IOUSBInterfaceInterface** _interface = nullptr;
    bool _open = false;
};
