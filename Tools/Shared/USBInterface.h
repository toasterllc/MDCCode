#pragma once
#include <IOKit/IOKitLib.h>
#include "SendRight.h"

class USBInterface {
public:
    // Default constructor: empty
    USBInterface() {}
    
    // Constructor: accept a SendRight
    USBInterface(SendRight&& service) {
        try {
            assert(service);
            
            IOCFPlugInInterface** plugin = nullptr;
            SInt32 score = 0;
            kern_return_t kr = IOCreatePlugInInterfaceForService(service.port(), kIOUSBInterfaceUserClientTypeID,
                kIOCFPlugInInterfaceID, &plugin, &score);
            if (kr != KERN_SUCCESS) throw std::runtime_error("IOCreatePlugInInterfaceForService failed");
            if (!plugin) throw std::runtime_error("IOCreatePlugInInterfaceForService returned NULL plugin");
            
            IOUSBInterfaceInterface** interface = nullptr;
            HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                (LPVOID*)&interface);
            // Release `plugin` before checking for error, so we don't
            // leak it if QueryInterface fails
            (*plugin)->Release(plugin);
            if (hr) throw std::runtime_error("QueryInterface failed");
            
            _setInterface(interface);
        
        } catch (...) {
            _reset();
        }
    }
    
    // Constructor: take ownership of a IOUSBInterfaceInterface
    USBInterface(IOUSBInterfaceInterface** interface) {
        _setInterface(interface);
    }
    
    // Copy constructor: illegal
    USBInterface(const USBInterface&) = delete;
    // Move constructor: use move assignment operator
    USBInterface(USBInterface&& x) { *this = std::move(x); }
    // Move assignment operator
    USBInterface& operator=(USBInterface&& x) {
        _interface = x._interface;
        x._interface = nullptr;
        return *this;
    }
    
    ~USBInterface() {
        _reset();
    }
    
    IOUSBInterfaceInterface** interface() {
        assert(_interface);
        return _interface;
    }
    
    operator bool() const { return _interface; }
    
private:
    // Take ownership of a IOUSBInterfaceInterface
    void _setInterface(IOUSBInterfaceInterface** interface) {
        assert(!_interface);
        _interface = interface;
        // Open the interface
        IOReturn ior = (*_interface)->USBInterfaceOpen(_interface);
        if (ior != kIOReturnSuccess) throw std::runtime_error("USBInterfaceOpen failed");
    }
    
    void _reset() {
        if (_interface) {
            (*_interface)->USBInterfaceClose(_interface);
            (*_interface)->Release(_interface);
            _interface = nullptr;
        }
    }
    
    IOUSBInterfaceInterface** _interface = nullptr;
};
