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
            
            _interface = interface;
            // Open the device
            IOReturn ior = (*_interface)->USBDeviceOpen(_interface);
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
        _interface = x._interface;
        if (_interface) (*_interface)->AddRef(_interface);
        return *this;
    }
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
    
    IOUSBDeviceInterface** interface() const {
        assert(_interface);
        return _interface;
    }
    
    operator bool() const { return _interface; }
    
    std::vector<USBInterface> usbInterfaces() {
        if (!_usbInterfacesInit) {
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
                _usbInterfaces.emplace_back(std::move(service));
            }
            _usbInterfacesInit = true;
        }
        return _usbInterfaces;
    }
    
    IOReturn vendorRequestOut(uint8_t req, void* data, size_t len) const {
        IOUSBDevRequest usbReq = {
            .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
            .bRequest       = req,
            .pData          = data,
            .wLength        = (uint16_t)len
        };
        return (*_interface)->DeviceRequest(_interface, &usbReq);
    }
    
private:
    
    void _reset() {
        if (_interface) {
            // We don't call USBDeviceClose here!
            // We allow USBDevice to be copied, and the copies assume
            // the device is open.
            // It'll be closed when the object is deallocated.
            (*_interface)->Release(_interface);
            _interface = nullptr;
        }
    }
    
    IOUSBDeviceInterface** _interface = nullptr;
    std::vector<USBInterface> _usbInterfaces;
    bool _usbInterfacesInit = false;
};
