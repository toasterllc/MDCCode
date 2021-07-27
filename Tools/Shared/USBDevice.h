#pragma once

#if __APPLE__
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/IOCFPlugIn.h>
#include "SendRight.h"
#elif __linux__
#include <libusb-1.0/libusb.h>
#endif

#include <vector>
#include <set>
#include <memory>
#include <mutex>
#include <cassert>
#include "Toastbox/USB.h"
#include "Toastbox/RefCounted.h"
#include "Toastbox/RuntimeError.h"
#include "Toastbox/Defer.h"

class USBDevice {
public:
    using Milliseconds = std::chrono::milliseconds;
    static constexpr inline Milliseconds Forever = Milliseconds::max();
    class Interface;
    
    class Pipe {
    public:
        Pipe(Interface& interface, uint8_t pipeRef, uint8_t epAddr) : 
        _interface(interface), _pipeRef(pipeRef), _epAddr(epAddr) {}
        
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
    
#if __APPLE__
    
private:
    template <typename T>
    static void _Retain(T** x) { (*x)->AddRef(x); }
    
    template <typename T>
    static void _Release(T** x) { (*x)->Release(x); }
    
    using _IOCFPlugInInterface = RefCounted<IOCFPlugInInterface**, _Retain<IOCFPlugInInterface>, _Release<IOCFPlugInInterface>>;
    using _IOUSBDeviceInterface = RefCounted<IOUSBDeviceInterface**, _Retain<IOUSBDeviceInterface>, _Release<IOUSBDeviceInterface>>;
    using _IOUSBInterfaceInterface = RefCounted<IOUSBInterfaceInterface**, _Retain<IOUSBInterfaceInterface>, _Release<IOUSBInterfaceInterface>>;
    
public:
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
                
                for (uint8_t pipeRef=1; pipeRef<=epCount; pipeRef++) {
                    IOUSBEndpointProperties props = { .bVersion = kUSBEndpointPropertiesVersion3 };
                    ior = iokitExec<&IOUSBInterfaceInterface::GetPipePropertiesV3>(pipeRef, &props);
                    _CheckErr(ior, "GetPipePropertiesV3() failed");
                    
                    const uint8_t epAddr = (props.bDirection==kUSBIn ? USB::Endpoint::DirIn : USB::Endpoint::DirOut)|props.bEndpointNumber;
                    _pipes.push_back(std::make_unique<Pipe>(*this, pipeRef, epAddr));
                }
            }
        }
        
        // Copying/moving aren't allowed because each Pipe within _pipes has a reference
        // to this particular instance, so it can't move.
        Interface(const Interface& x) = delete;
        Interface& operator=(const Interface& x) = delete;
        Interface(Interface&& x) = delete;
        Interface& operator=(Interface&& x) = delete;
        
        template <typename T>
        void read(const Pipe& p, T& t, Milliseconds timeout=Forever) {
            read(p, (void*)&t, sizeof(t), timeout);
        }
        
        void read(const Pipe& p, void* buf, size_t len, Milliseconds timeout=Forever) {
            _openIfNeeded();
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
        
        template <typename T>
        void write(const Pipe& p, T& x, Milliseconds timeout=Forever) {
            write(p, (void*)&x, sizeof(x), timeout);
        }
        
        void write(const Pipe& p, const void* buf, size_t len, Milliseconds timeout=Forever) {
            _openIfNeeded();
            if (timeout == Forever) {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::WritePipe>(p._pipeRef, (void*)buf, (uint32_t)len);
                _CheckErr(ior, "WritePipe() failed");
            } else {
                IOReturn ior = iokitExec<&IOUSBInterfaceInterface::WritePipeTO>(p._pipeRef, (void*)buf, (uint32_t)len, 0, (uint32_t)timeout.count());
                _CheckErr(ior, "WritePipeTO() failed");
            }
        }
        
        void reset(const Pipe& p) {
            _openIfNeeded();
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
        void _openIfNeeded() {
            if (_open) return;
            // Open the interface
            IOReturn ior = iokitExec<&IOUSBInterfaceInterface::USBInterfaceOpen>();
            _CheckErr(ior, "USBInterfaceOpen() failed");
            _open = true;
        }
        
        _IOUSBInterfaceInterface _iokitInterface;
        bool _open = false;
        std::vector<std::unique_ptr<Pipe>> _pipes; // Using unique_ptr since Pipe has a deleted move+copy constructors
    };

#elif __linux__

    class Interface {
    public:
        Interface(USBDevice& dev, const struct libusb_interface& iface) :
        _dev(dev), _idx(_GetInterfaceIdx(iface)) {
            std::set<uint8_t> epAddrs;
            for (int i=0; i<iface.num_altsetting; i++) {
                const struct libusb_interface_descriptor& ifaceDesc = iface.altsetting[i];
                for (uint8_t ii=0; ii<ifaceDesc.bNumEndpoints; ii++) {
                    const struct libusb_endpoint_descriptor& endpointDesc = ifaceDesc.endpoint[ii];
                    epAddrs.insert(endpointDesc.bEndpointAddress);
                }
            }
            
            for (uint8_t epAddr : epAddrs) {
                _pipes.push_back(std::make_unique<Pipe>(*this, 0, epAddr));
            }
        }
        
        // Copying/moving aren't allowed because each Pipe within _pipes has a reference
        // to this particular instance, so it can't move.
        Interface(const Interface& x) = delete;
        Interface& operator=(const Interface& x) = delete;
        Interface(Interface&& x) = delete;
        Interface& operator=(Interface&& x) = delete;
        
        template <typename T>
        void read(const Pipe& p, T& t, Milliseconds timeout=Forever) {
            read(p, (void*)&t, sizeof(t), timeout);
        }
        
        void read(const Pipe& p, void* buf, size_t len, Milliseconds timeout=Forever) {
            _openIfNeeded();
            int xferLen = 0;
            int ir = libusb_bulk_transfer(_devHandle, p._epAddr, (uint8_t*)buf, (int)len, &xferLen,
                _libusbTimeoutFromMs(timeout));
            _CheckErr(ir, "libusb_bulk_transfer failed");
            if ((size_t)xferLen != len)
                throw RuntimeError("libusb_bulk_transfer short read (tried: %zu, got: %zu)", len, (size_t)xferLen);
        }
        
        template <typename T>
        void write(const Pipe& p, T& x, Milliseconds timeout=Forever) {
            write(p, (void*)&x, sizeof(x), timeout);
        }
        
        void write(const Pipe& p, const void* buf, size_t len, Milliseconds timeout=Forever) {
            _openIfNeeded();
            int xferLen = 0;
            int ir = libusb_bulk_transfer(_devHandle, p._epAddr, (uint8_t*)buf, (int)len, &xferLen,
                _libusbTimeoutFromMs(timeout));
            _CheckErr(ir, "libusb_bulk_transfer failed");
            if ((size_t)xferLen != len)
                throw RuntimeError("libusb_bulk_transfer short write (tried: %zu, got: %zu)", len, (size_t)xferLen);
        }
        
        void reset(const Pipe& p) {
            _openIfNeeded();
            #warning implement
        }
        
        const Pipe& getPipe(uint8_t epAddr) const {
            for (const auto& p : _pipes) {
                if (p->_epAddr == epAddr) return *p;
            }
            throw RuntimeError("no pipe matching endpoint address %x", epAddr);
        }
        
    private:
        static unsigned int _libusbTimeoutFromMs(Milliseconds timeout) {
            if (timeout == Forever) return 0;
            else if (timeout == Milliseconds::zero()) return 1;
            else return timeout.count();
        }
        
        static uint8_t _GetInterfaceIdx(const struct libusb_interface& iface) {
            if (iface.num_altsetting < 1) throw RuntimeError("num_altsetting<0: %d", iface.num_altsetting);
            return iface.altsetting[0].bInterfaceNumber;
        }
        
        void _openIfNeeded() {
            if (_devHandle) return;
            libusb_device_handle*const devHandle = _dev._open();
            int ir = libusb_claim_interface(_devHandle, _idx);
            _CheckErr(ir, "libusb_claim_interface failed");
            // Update `_devHandle` to signal that we've claimed the interface
            _devHandle = devHandle;
        }
        
        USBDevice& _dev;
        const uint8_t _idx = 0;
        libusb_device_handle* _devHandle = nullptr;
        std::vector<std::unique_ptr<Pipe>> _pipes; // Using unique_ptr since Pipe has a deleted move+copy constructors
    };
    
#endif
    
    
    
    
    
#if __APPLE__
    
    static std::vector<USBDevice> GetDevices() {
        std::vector<USBDevice> devices;
        io_iterator_t ioServicesIter = MACH_PORT_NULL;
        kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &ioServicesIter);
        if (kr != KERN_SUCCESS) throw RuntimeError("IOServiceGetMatchingServices failed: 0x%x", kr);
        
        SendRight servicesIter(ioServicesIter);
        while (servicesIter) {
            SendRight service(IOIteratorNext(servicesIter));
            if (!service.valid()) break;
            // Ignore devices that we fail to create a USBDevice for
            try { devices.emplace_back(service); }
            catch (...) {}
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
    
    USBDevice(const SendRight& service) : _service(service) {
        assert(service);
        
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
                if (!service.valid()) break;
                _interfaces.push_back(std::make_unique<Interface>(std::move(service)));
            }
        }
    }
    
    // Move constructor: use default implementation
    // For some reason the default move implementation is deleted when we have _both_ a
    // `RefCounted` member and a `std::vector<std::unique_ptr<Interface>>` member. When
    // we only one exists, the default move implementation exists.
    USBDevice(USBDevice&& x) = default;
    
    USB::DeviceDescriptor deviceDescriptor() const {
        // Apple's APIs don't provide a way to get the device descriptor, only
        // the configuration descriptor (GetConfigurationDescriptorPtr).
        // However in our testing, no IO actually occurs with the device when
        // requesting its device descriptor, so the kernel must intercept the
        // request and return a cached copy. So in short, requesting the
        // device descriptor shouldn't be too expensive.
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
//        _openIfNeeded();
        
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
    
//    void _openIfNeeded() {
//        if (_open) return;
//        // Open the device
//        IOReturn ior = iokitExec<&IOUSBDeviceInterface::USBDeviceOpen>();
//        _CheckErr(ior, "USBDeviceOpen() failed");
//        _open = true;
//    }
    
    SendRight _service;
    _IOUSBDeviceInterface _iokitInterface;
    std::vector<std::unique_ptr<Interface>> _interfaces;
//    bool _open = false;
    
#elif __linux__
    
    static std::vector<USBDevice> GetDevices() {
        libusb_device** devs = nullptr;
        ssize_t devsCount = libusb_get_device_list(_USBCtx(), &devs);
        _CheckErr((int)devsCount, "libusb_get_device_list failed");
        Defer( if (devs) libusb_free_device_list(devs, true); );
        
        std::vector<USBDevice> r;
        for (size_t i=0; i<(size_t)devsCount; i++) {
            r.push_back(devs[i]);
        }
        return r;
    }
    
    USBDevice(libusb_device* dev) : _dev(dev) {
        assert(dev);
        
        // Populate _interfaces
        {
            struct libusb_config_descriptor* configDesc = nullptr;
            int ir = libusb_get_config_descriptor(_dev, 0, &configDesc);
            _CheckErr(ir, "libusb_config_descriptor failed");
            
            for (uint8_t i=0; i<configDesc->bNumInterfaces; i++) {
                const struct libusb_interface& iface = configDesc->interface[i];
                _interfaces.push_back(std::make_unique<Interface>(*this, iface));
            }
        }
    }
    
    USB::DeviceDescriptor deviceDescriptor() const {
        struct libusb_device_descriptor desc;
        int ir = libusb_get_device_descriptor(_dev, &desc);
        _CheckErr(ir, "libusb_get_device_descriptor failed");
        
        return USB::DeviceDescriptor{
            .bLength                = desc.bLength,
            .bDescriptorType        = desc.bDescriptorType,
            .bcdUSB                 = desc.bcdUSB,
            .bDeviceClass           = desc.bDeviceClass,
            .bDeviceSubClass        = desc.bDeviceSubClass,
            .bDeviceProtocol        = desc.bDeviceProtocol,
            .bMaxPacketSize0        = desc.bMaxPacketSize0,
            .idVendor               = desc.idVendor,
            .idProduct              = desc.idProduct,
            .bcdDevice              = desc.bcdDevice,
            .iManufacturer          = desc.iManufacturer,
            .iProduct               = desc.iProduct,
            .iSerialNumber          = desc.iSerialNumber,
            .bNumConfigurations     = desc.bNumConfigurations,
        };
    }
    
    const Interface& getInterface(uint8_t idx) const { return *_interfaces.at(idx); }
    
private:
    static libusb_context* _USBCtx() {
        static std::once_flag Once;
        static libusb_context* Ctx = nullptr;
        std::call_once(Once, [](){
            int ir = libusb_init(&Ctx);
            _CheckErr(ir, "libusb_init failed");
        });
        return Ctx;
    }
    
    static void _CheckErr(int ir, const char* errMsg) {
        if (ir < 0) throw RuntimeError("%s: %s", errMsg, libusb_error_name(ir));
    }
    
    libusb_device_handle* _open() {
        if (_devHandle) return _devHandle;
        int ir = libusb_open(_dev, &_devHandle);
        _CheckErr(ir, "libusb_open failed");
        return _devHandle;
    }
    
    libusb_device* _dev = nullptr;
    libusb_device_handle* _devHandle = nullptr;
    std::vector<std::unique_ptr<Interface>> _interfaces;
    
    friend Interface;
    
#endif
};
