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
        try {
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
            
            _setInterface(interface);
        
        } catch (...) {
            _reset();
        }
    }
    
    // Constructor: take ownership of a IOUSBDeviceInterface
    USBDevice(IOUSBDeviceInterface** interface) {
        _setInterface(interface);
    }
    
    // Copy constructor: illegal
    USBDevice(const USBDevice&) = delete;
    // Move constructor: use move assignment operator
    USBDevice(USBDevice&& x) { *this = std::move(x); }
    // Move assignment operator
    USBDevice& operator=(USBDevice&& x) {
        _interface = x._interface;
        x._interface = nullptr;
        return *this;
    }
    
    ~USBDevice() {
        _reset();
    }
    
    IOUSBDeviceInterface** interface() {
        assert(_interface);
        return _interface;
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
        IOUSBDevRequest usbReq = {
            .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
            .bRequest       = req,
            .pData          = data,
            .wLength        = (uint16_t)len
        };
        return (*_interface)->DeviceRequest(_interface, &usbReq);
    }
    
private:
    // Take ownership of a IOUSBDeviceInterface
    void _setInterface(IOUSBDeviceInterface** interface) {
        assert(!_interface);
        _interface = interface;
        // Open the interface
        IOReturn ior = (*_interface)->USBDeviceOpen(_interface);
        if (ior != kIOReturnSuccess) throw std::runtime_error("USBDeviceOpen failed");
    }
    
    void _reset() {
        if (_interface) {
            (*_interface)->USBDeviceClose(_interface);
            (*_interface)->Release(_interface);
            _interface = nullptr;
        }
    }
    
    IOUSBDeviceInterface** _interface = nullptr;
    bool _open = false;
};
