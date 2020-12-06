#pragma once
#include <IOKit/IOKitLib.h>
#include "SendRight.h"
#include "USBInterface.h"

class USBDevice {
public:
    // Default constructor: empty
    USBDevice() {}
    
    // Constructor: accept a SendRight
    USBDevice(SendRight&& service) {
        assert(service);
        
        IOCFPlugInInterface** plugin = nullptr;
        SInt32 score = 0;
        IOReturn kr = IOCreatePlugInInterfaceForService(service.port(), kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID, &plugin, &score);
        if (kr != KERN_SUCCESS) throw std::runtime_error("IOCreatePlugInInterfaceForService failed");
        if (!plugin) throw std::runtime_error("IOCreatePlugInInterfaceForService returned NULL plugin");
        
        IOUSBDeviceInterface** interface = nullptr;
        HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
            (LPVOID*)&interface);
        // Release `plugin` before checking for error, so we don't
        // leak it if QueryInterface fails
        (*plugin)->Release(plugin);
        if (hr) throw std::runtime_error("QueryInterface failed");
        
        setInterface(interface);
    }
    
    // Constructor: take ownership of a IOUSBDeviceInterface
    USBDevice(IOUSBDeviceInterface** interface) {
        setInterface(interface);
    }
    
    // Copy constructor: illegal
    USBDevice(const USBDevice&) = delete;
    // Move constructor: use move assignment operator
    USBDevice(USBDevice&& x) { *this = std::move(x); }
    // Move assignment operator
    USBDevice& operator=(USBDevice&& x) {
        // Retain the interface on behalf of `set`
        auto interface = x._interface;
        if (interface) (*interface)->AddRef(interface);
        
        x.setInterface(nullptr); // Reset x's interface first, so that it calls USBDeviceClose before we call USBDeviceOpen
        setInterface(interface);
        return *this;
    }
    
    ~USBDevice() {
        setInterface(nullptr);
    }
    
    IOUSBDeviceInterface** interface() {
        assert(_interface);
        return _interface;
    }
    
    // Take ownership of a IOUSBDeviceInterface
    void setInterface(IOUSBDeviceInterface** interface) {
        if (_interface) {
            if (_open) (*_interface)->USBDeviceClose(_interface);
            (*_interface)->Release(_interface);
        }
        
        _interface = interface;
        _open = false;
    }
    
    operator bool() const { return _interface; }
    
    std::vector<USBInterface> usbInterfaces() {
        std::vector<USBInterface> interfaces;
        io_iterator_t ioServicesIter = MACH_PORT_NULL;
        IOUSBFindInterfaceRequest req = {
            .bInterfaceClass = kIOUSBFindInterfaceDontCare,
            .bInterfaceSubClass = kIOUSBFindInterfaceDontCare,
            .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
            .bAlternateSetting = kIOUSBFindInterfaceDontCare,
        };
        IOReturn ior = (*_interface)->CreateInterfaceIterator(_interface, &req, &ioServicesIter);
        if (ior != kIOReturnSuccess) throw std::runtime_error("CreateInterfaceIterator failed");
        
        SendRight servicesIter(ioServicesIter);
        while (servicesIter) {
            SendRight service(IOIteratorNext(servicesIter.port()));
            if (!service) break;
            interfaces.emplace_back(std::move(service));
        }
        return interfaces;
    }
    
    IOReturn vendorRequestOut(uint8_t req, void* data, size_t len) {
        _openIfNeeded();
        IOUSBDevRequest usbReq = {
            .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
            .bRequest       = req,
            .pData          = data,
            .wLength        = (uint16_t)len
        };
        return (*_interface)->DeviceRequest(_interface, &usbReq);
    }
    
private:
    void _openIfNeeded() {
        if (!_open) {
            (*_interface)->USBDeviceOpen(_interface);
            _open = true;
        }
    }
    
    IOUSBDeviceInterface** _interface = nullptr;
    bool _open = false;
};
