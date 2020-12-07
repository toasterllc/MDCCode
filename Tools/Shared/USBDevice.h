#pragma once
#include <IOKit/IOKitLib.h>
#include <vector>
#include "SendRight.h"
#include "USBInterface.h"
#include "RuntimeError.h"

class USBDevice {
public:
    template <typename T>
    static std::vector<T> FindDevices(uint16_t vid, uint16_t pid) {
        std::vector<T> devices;
        NSMutableDictionary* match = CFBridgingRelease(IOServiceMatching(kIOUSBDeviceClassName));
        match[@kIOPropertyMatchKey] = @{
            @"idVendor": @(vid),
            @"idProduct": @(pid),
        };
        
        io_iterator_t ioServicesIter = MACH_PORT_NULL;
        kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, (CFDictionaryRef)CFBridgingRetain(match), &ioServicesIter);
        if (kr != KERN_SUCCESS) throw RuntimeError("IOServiceGetMatchingServices failed: %x", kr);
        
        SendRight servicesIter(ioServicesIter);
        while (servicesIter) {
            SendRight service(IOIteratorNext(servicesIter.port()));
            if (!service) break;
            try {
                T device(std::move(service));
                devices.push_back(device);
            } catch (...) {}
        }
        return devices;
    }
    
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
            
            _state.interface = interface;
            // Open the device
            IOReturn ior = (*_state.interface)->USBDeviceOpen(_state.interface);
            if (ior != kIOReturnSuccess) throw std::runtime_error("USBDeviceOpen failed");
        
        } catch (...) {
            _reset();
            throw;
        }
    }
    
    // Copy constructor: use copy assignment operator
    USBDevice(const USBDevice& x) { *this = x; }
    // Copy assignment operator
    USBDevice& operator=(const USBDevice& x) {
        _state = x._state;
        if (_state.interface) (*_state.interface)->AddRef(_state.interface);
        return *this;
    }
    // Move constructor: use move assignment operator
    USBDevice(USBDevice&& x) { *this = std::move(x); }
    // Move assignment operator
    USBDevice& operator=(USBDevice&& x) {
        _state = x._state;
        x._state = {};
        return *this;
    }
    
    ~USBDevice() {
        _reset();
    }
    
    IOUSBDeviceInterface** interface() const {
        assert(_state.interface);
        return _state.interface;
    }
    
    operator bool() const { return _state.interface; }
    
    std::vector<USBInterface> usbInterfaces() {
        if (!_state.usbInterfacesInit) {
            io_iterator_t ioServicesIter = MACH_PORT_NULL;
            IOUSBFindInterfaceRequest req = {
                .bInterfaceClass = kIOUSBFindInterfaceDontCare,
                .bInterfaceSubClass = kIOUSBFindInterfaceDontCare,
                .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
                .bAlternateSetting = kIOUSBFindInterfaceDontCare,
            };
            IOReturn ior = (*_state.interface)->CreateInterfaceIterator(_state.interface, &req, &ioServicesIter);
            if (ior != kIOReturnSuccess) throw std::runtime_error("CreateInterfaceIterator failed");
            
            SendRight servicesIter(ioServicesIter);
            while (servicesIter) {
                SendRight service(IOIteratorNext(servicesIter.port()));
                if (!service) break;
                _state.usbInterfaces.emplace_back(std::move(service));
            }
            _state.usbInterfacesInit = true;
        }
        return _state.usbInterfaces;
    }
    
    void vendorRequestOut(uint8_t req, void* data, size_t len) const {
        IOUSBDevRequest usbReq = {
            .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
            .bRequest       = req,
            .pData          = data,
            .wLength        = (uint16_t)len
        };
        IOReturn ior = (*_state.interface)->DeviceRequest(_state.interface, &usbReq);
        if (ior != kIOReturnSuccess) throw RuntimeError("DeviceRequest() failed: %x", ior);
    }
    
private:
    
    void _reset() {
        if (_state.interface) {
            // We don't call USBDeviceClose here!
            // We allow USBDevice to be copied, and the copies assume
            // the device is open.
            // It'll be closed when the object is deallocated.
            (*_state.interface)->Release(_state.interface);
            _state.interface = nullptr;
        }
    }
    
    struct {
        IOUSBDeviceInterface** interface = nullptr;
        std::vector<USBInterface> usbInterfaces;
        bool usbInterfacesInit = false;
    } _state;
};
