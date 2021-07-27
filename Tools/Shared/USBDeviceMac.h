#pragma once
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <vector>
#include <memory>
#include <cassert>
#include "Toastbox/USB.h"
#include "Toastbox/RefCounted.h"
#include "SendRight.h"
#include "RuntimeError.h"

class USBDevice {
private:
    template <typename T>
    static void _Retain(T** x) { (*x)->AddRef(x); }
    
    template <typename T>
    static void _Release(T** x) { (*x)->Release(x); }
    
    using _IOCFPlugInInterface = RefCounted<IOCFPlugInInterface**, _Retain<IOCFPlugInInterface>, _Release<IOCFPlugInInterface>>;
    using _IOUSBDeviceInterface = RefCounted<IOUSBDeviceInterface**, _Retain<IOUSBDeviceInterface>, _Release<IOUSBDeviceInterface>>;
    using _IOUSBInterfaceInterface = RefCounted<IOUSBInterfaceInterface**, _Retain<IOUSBInterfaceInterface>, _Release<IOUSBInterfaceInterface>>;
    
public:
    using Milliseconds = std::chrono::milliseconds;
    static constexpr inline Milliseconds Forever = Milliseconds::max();
    class Interface;
    
    class Pipe {
    public:
        Pipe(Interface& interface, uint8_t pipeRef, uint8_t epAddr) : 
        _interface(interface), _pipeRef(pipeRef), _epAddr(epAddr) {}
        
//        // Copy constructor: illegal
//        Pipe(const Pipe& x) = delete;
//        // Copy assignment operator: illegal
//        Pipe& operator=(const Pipe& x) = delete;
//        // Move constructor: illegal
//        Pipe(Pipe&& x) = delete;
//        // Move assignment operator: illegal
//        Pipe& operator=(Pipe&& x) = delete;
        
        template <typename T>
        void write(T& x, Milliseconds timeout=Forever) const { _interface.write(*this, x, timeout); }
        void write(const void* buf, size_t len, Milliseconds timeout=Forever) const { _interface.write(*this, buf, len, timeout); }
        
        template <typename T>
        void read(T& t, Milliseconds timeout=Forever) const { _interface.read(*this, t, timeout); }
        void read(void* buf, size_t len, Milliseconds timeout=Forever) const { _interface.read(*this, buf, len, timeout); }
        void reset() const { _interface.reset(*this); }
        
    private:
        Interface& _interface;
        uint8_t _pipeRef = 0;
        uint8_t _epAddr = 0;
        
        friend class Interface;
    };
    
    class Interface {
    public:
        template <auto Fn, typename... Args>
        auto iokitExec(Args... args) const {
            assert(_iokitInterface);
            return ((*_iokitInterface)->*Fn)(_iokitInterface, args...);
        }
        
        template <auto Fn, typename... Args>
        auto iokitExec(Args... args) {
            assert(_iokitInterface);
            return ((*_iokitInterface)->*Fn)(_iokitInterface, args...);
        }
        
        // Constructor: accept a SendRight
        Interface(SendRight&& service) {
            assert(service);
            
            _IOCFPlugInInterface plugin;
            {
                IOCFPlugInInterface** tmp = nullptr;
                SInt32 score = 0;
                kern_return_t kr = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
                    kIOCFPlugInInterfaceID, &tmp, &score);
                if (kr != KERN_SUCCESS) throw std::runtime_error("IOCreatePlugInInterfaceForService failed");
                if (!tmp) throw std::runtime_error("IOCreatePlugInInterfaceForService returned NULL plugin");
                plugin = tmp;
            }
            
            {
                IOUSBInterfaceInterface** tmp = nullptr;
                HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID*)&tmp);
                if (hr) throw std::runtime_error("QueryInterface failed");
                _iokitInterface = tmp;
            }
            
            // Populate _pipes
            {
                uint8_t epCount = 0;
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::GetNumEndpoints>(&epCount);
                _CheckErr(ior, "GetNumEndpoints() failed");
                
                for (uint8_t pipeRef=1; pipeRef<epCount; pipeRef++) {
                    IOUSBEndpointProperties props = { .bVersion = kUSBEndpointPropertiesVersion3 };
                    ior = iokitExec<&IOUSBInterfaceInterface::GetPipePropertiesV3>(pipeRef, &props);
                    _CheckErr(ior, "GetPipePropertiesV3() failed");
                    
                    const uint8_t epAddr = (props.bDirection==kUSBIn ? USB::Endpoint::DirIn : USB::Endpoint::DirOut)|props.bEndpointNumber;
                    _pipes.push_back(std::make_unique<Pipe>(*this, pipeRef, epAddr));
                }
            }
            
            // Open the interface
            IOReturn ior = iokitExec<&IOUSBInterfaceInterface::USBInterfaceOpen>();
            _CheckErr(ior, "USBInterfaceOpen() failed");
        }
        
        // Copying/moving aren't allowed because each Pipe within _pipes has a reference
        // to this particular instance, so it can't move.
        Interface(const Interface& x) = delete;
        Interface& operator=(const Interface& x) = delete;
        Interface(Interface&& x) = delete;
        Interface& operator=(Interface&& x) = delete;
        
        template <typename T>
        void write(const Pipe& p, T& x, Milliseconds timeout=Forever) const {
            if (timeout == Forever) {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::WritePipe>(p._pipeRef, (void*)&x, (uint32_t)sizeof(x));
                _CheckErr(ior, "WritePipe() failed");
            } else {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::WritePipeTO>(p._pipeRef, (void*)&x, (uint32_t)sizeof(x), 0, (uint32_t)timeout.count());
                _CheckErr(ior, "WritePipeTO() failed");
            }
        }
        
        void write(const Pipe& p, const void* buf, size_t len, Milliseconds timeout=Forever) const {
            if (timeout == Forever) {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::WritePipe>(p._pipeRef, (void*)buf, (uint32_t)len);
                _CheckErr(ior, "WritePipe() failed");
            } else {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::WritePipeTO>(p._pipeRef, (void*)buf, (uint32_t)len, 0, (uint32_t)timeout.count());
                _CheckErr(ior, "WritePipeTO() failed");
            }
        }
        
        template <typename T>
        void read(const Pipe& p, T& t, Milliseconds timeout=Forever) const {
            uint32_t len32 = (uint32_t)sizeof(t);
            if (timeout == Forever) {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::ReadPipe>(p._pipeRef, &t, &len32);
                _CheckErr(ior, "ReadPipe() failed");
            } else {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::ReadPipeTO>(p._pipeRef, &t, &len32, 0, (uint32_t)timeout.count());
                _CheckErr(ior, "ReadPipeTO() failed");
            }
            
            if (len32 != sizeof(t)) throw RuntimeError("ReadPipe() returned bad length (expected %ju bytes, got %ju bytes)",
                (uintmax_t)sizeof(t), (uintmax_t)len32);
        }
        
        void read(const Pipe& p, void* buf, size_t len, Milliseconds timeout=Forever) const {
            uint32_t len32 = (uint32_t)len;
            if (timeout == Forever) {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::ReadPipe>(p._pipeRef, buf, &len32);
                _CheckErr(ior, "ReadPipe() failed");
            } else {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::ReadPipeTO>(p._pipeRef, buf, &len32, 0, (uint32_t)timeout.count());
                _CheckErr(ior, "ReadPipeTO() failed");
            }
            
            if (len32 != len) throw RuntimeError("ReadPipe() returned bad length (expected %ju bytes, got %ju bytes)",
                (uintmax_t)len, (uintmax_t)len32);
        }
        
        void reset(const Pipe& p) const {
            IOReturn ior = iokitExec<&IOUSBInterfaceInterface::ResetPipe>(p._pipeRef);
            _CheckErr(ior, "ResetPipe() failed");
        }
        
        const Pipe& getPipe(uint8_t epAddr) const {
            for (const auto& p : _pipes) {
                if (p->_epAddr == epAddr) return *p;
            }
            throw RuntimeError("no pipe matching endpoint address %x", epAddr);
        }
        
    private:
        _IOUSBInterfaceInterface _iokitInterface;
        std::vector<std::unique_ptr<Pipe>> _pipes; // Using unique_ptr since Pipe has a deleted move+copy constructors
    };
    
    
    
    
    
    
    
    static std::vector<USBDevice> GetDevices() {
        std::vector<USBDevice> devices;
        io_iterator_t ioServicesIter = MACH_PORT_NULL;
        kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &ioServicesIter);
        if (kr != KERN_SUCCESS) throw RuntimeError("IOServiceGetMatchingServices failed: 0x%x", kr);
        
        SendRight servicesIter(ioServicesIter);
        while (servicesIter) {
            SendRight service(IOIteratorNext(servicesIter));
            if (!service) break;
            devices.emplace_back(service);
        }
        return devices;
    }
    
    template <auto Fn, typename... Args>
    auto iokitExec(Args... args) const {
        assert(_iokitInterface);
        return ((*_iokitInterface)->*Fn)(_iokitInterface, args...);
    }
    
    template <auto Fn, typename... Args>
    auto iokitExec(Args... args) {
        assert(_iokitInterface);
        return ((*_iokitInterface)->*Fn)(_iokitInterface, args...);
    }
    
    // Constructor: accept a SendRight
    USBDevice(const SendRight& service) {
        assert(service);
        
        _service = service;
        
        _IOCFPlugInInterface plugin;
        {
            IOCFPlugInInterface** tmp = nullptr;
            SInt32 score = 0;
            IOReturn kr = IOCreatePlugInInterfaceForService(_service, kIOUSBDeviceUserClientTypeID,
                kIOCFPlugInInterfaceID, &tmp, &score);
            if (kr != KERN_SUCCESS) throw std::runtime_error("IOCreatePlugInInterfaceForService failed");
            if (!tmp) throw std::runtime_error("IOCreatePlugInInterfaceForService returned NULL plugin");
            plugin = tmp;
        }
        
        {
            IOUSBDeviceInterface** tmp = nullptr;
            HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*)&tmp);
            if (hr) throw std::runtime_error("QueryInterface failed");
            _iokitInterface = tmp;
        }
        
        // Populate _interfaces
        {
            io_iterator_t ioServicesIter = MACH_PORT_NULL;
            IOUSBFindInterfaceRequest req = {
                .bInterfaceClass = kIOUSBFindInterfaceDontCare,
                .bInterfaceSubClass = kIOUSBFindInterfaceDontCare,
                .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
                .bAlternateSetting = kIOUSBFindInterfaceDontCare,
            };
            
            IOReturn ior = iokitExec<&IOUSBDeviceInterface::CreateInterfaceIterator>(&req, &ioServicesIter);
            _CheckErr(ior, "CreateInterfaceIterator() failed");
            
            SendRight servicesIter(ioServicesIter);
            while (servicesIter) {
                SendRight service(IOIteratorNext(servicesIter));
                if (!service) break;
                _interfaces.push_back(std::make_unique<Interface>(std::move(service)));
            }
        }
        
        // Open the device
        IOReturn ior = iokitExec<&IOUSBDeviceInterface::USBDeviceOpen>();
        _CheckErr(ior, "USBDeviceOpen() failed");
    }
    
//    // Copy constructor: illegal
//    USBDevice(const USBDevice& x) = delete;
//    // Copy assignment operator: illegal
//    USBDevice& operator=(const USBDevice& x) = delete;
//    // Move constructor: illegal
//    USBDevice(USBDevice&& x) = delete;
//    // Move assignment operator: illegal
//    USBDevice& operator=(USBDevice&& x) = delete;
    
//    // Copy constructor: use copy assignment operator
//    USBDevice(const USBDevice& x) { *this = x; }
//    // Copy assignment operator
//    USBDevice& operator=(const USBDevice& x) {
//        return *this;
//    }
    // Move constructor: use move assignment operator
    USBDevice(USBDevice&& x) = default;
//    // Move assignment operator
//    USBDevice& operator=(USBDevice&& x) {
//        _service = std::move(x._service);
//        _iokitInterface = std::move(x._iokitInterface);
//        _interfaces = std::move(x._interfaces);
//        return *this;
//    }
    
    USB::DeviceDescriptor deviceDescriptor() const {
        using namespace Endian;
        USB::DeviceDescriptor desc;
        IOUSBDevRequest req = {
            .bmRequestType  = USBmakebmRequestType(kUSBIn, kUSBStandard, kUSBDevice),
            .bRequest       = kUSBRqGetDescriptor,
            .wValue         = kUSBDeviceDesc<<8,
            .wLength        = sizeof(desc),
            .pData          = &desc,
        };
        
        IOReturn ior = iokitExec<&IOUSBDeviceInterface::DeviceRequest>(&req);
        _CheckErr(ior, "DeviceRequest() failed");
        
        desc.bLength                = HFL(desc.bLength);
        desc.bDescriptorType        = HFL(desc.bDescriptorType);
        desc.bcdUSB                 = HFL(desc.bcdUSB);
        desc.bDeviceClass           = HFL(desc.bDeviceClass);
        desc.bDeviceSubClass        = HFL(desc.bDeviceSubClass);
        desc.bDeviceProtocol        = HFL(desc.bDeviceProtocol);
        desc.bMaxPacketSize0        = HFL(desc.bMaxPacketSize0);
        desc.idVendor               = HFL(desc.idVendor);
        desc.idProduct              = HFL(desc.idProduct);
        desc.bcdDevice              = HFL(desc.bcdDevice);
        desc.iManufacturer          = HFL(desc.iManufacturer);
        desc.iProduct               = HFL(desc.iProduct);
        desc.iSerialNumber          = HFL(desc.iSerialNumber);
        desc.bNumConfigurations     = HFL(desc.bNumConfigurations);
        return desc;
    }
    
    const Interface& getInterface(uint8_t idx) const { return *_interfaces.at(idx); }
    
    void vendorRequestOut(uint8_t req, void* data, size_t len) {
        IOUSBDevRequest usbReq = {
            .bmRequestType  = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice),
            .bRequest       = req,
            .pData          = data,
            .wLength        = (uint16_t)len
        };
        
        IOReturn ior = iokitExec<&IOUSBDeviceInterface::DeviceRequest>(&usbReq);
        _CheckErr(ior, "DeviceRequest() failed");
    }
    
private:
    static void _CheckErr(IOReturn ior, const char* errMsg) {
        if (ior != kIOReturnSuccess) throw RuntimeError("%s: %s", errMsg, mach_error_string(ior));
    }
    
    SendRight _service;
    _IOUSBDeviceInterface _iokitInterface;
    std::vector<std::unique_ptr<Interface>> _interfaces;
};
