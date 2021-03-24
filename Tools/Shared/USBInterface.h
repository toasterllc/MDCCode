#pragma once
#include <cassert>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/IOCFPlugIn.h>
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
            
            _interface = interface;
            // Open the interface
            IOReturn ior = (*_interface)->USBInterfaceOpen(_interface);
            if (ior != kIOReturnSuccess) {
                throw std::runtime_error("USBInterfaceOpen failed");
            }
        
        } catch (...) {
            _reset();
            throw;
        }
    }
    
    // Copy constructor: use copy assignment operator
    USBInterface(const USBInterface& x) { *this = x; }
    // Copy assignment operator
    USBInterface& operator=(const USBInterface& x) {
        _interface = x._interface;
        if (_interface) (*_interface)->AddRef(_interface);
        return *this;
    }
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
    
    IOUSBInterfaceInterface** interface() const {
        assert(_interface);
        return _interface;
    }
    
    operator bool() const { return _interface; }
    
private:
    void _reset() {
        if (_interface) {
            // We don't call USBInterfaceClose here!
            // We allow USBInterface to be copied, and the copies assume
            // the interface is open.
            // It'll be closed when the object is deallocated.
            (*_interface)->Release(_interface);
            _interface = nullptr;
        }
    }
    
    IOUSBInterfaceInterface** _interface = nullptr;
};
