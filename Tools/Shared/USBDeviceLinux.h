#pragma once
#include <libusb-1.0/libusb.h>
#include "Toastbox/Defer.h"

class USBDevice {
public:
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
    
    USBDevice() {}
    USBDevice(libusb_device* dev) {
        _setDev(dev);
    }
    
    // Copy constructor: not allowed
    USBDevice(const USBDevice& x) = delete;
    // Move constructor: use move assignment operator
    USBDevice(USBDevice&& x) { *this = std::move(x); }
    // Move assignment operator
    USBDevice& operator=(USBDevice&& x) {
        _reset();
        _s = x._s;
        x._s = {};
        return *this;
    }
    
    ~USBDevice() {
        _reset();
    }
    
    void open() {
        if (!_s.devHandle) {
            int ir = libusb_open(_s.dev, &_s.devHandle);
            _CheckErr(ir, "libusb_open failed");
        }
    }
    
    void close() {
        if (_s.devHandle) {
            libusb_close(_s.devHandle);
            _s.devHandle = nullptr;
        }
    }
    
    void claimInterface(uint8_t interfaceNum) {
        int ir = libusb_claim_interface(_s.devHandle, interfaceNum);
        _CheckErr(ir, "libusb_claim_interface failed");
    }
    
    void bulkRead(uint8_t ep, void* data, size_t len) {
        int xferLen = 0;
        int ir = libusb_bulk_transfer(_s.devHandle, ep, (uint8_t*)data, (int)len, &xferLen, 0);
        _CheckErr(ir, "libusb_bulk_transfer failed");
        if ((size_t)xferLen != len)
            throw RuntimeError("libusb_bulk_transfer short read (tried: %zu, got: %zu)", len, (size_t)xferLen);
    }
    
    void bulkWrite(uint8_t ep, const void* data, size_t len) {
        int xferLen = 0;
        int ir = libusb_bulk_transfer(_s.devHandle, ep, (uint8_t*)data, (int)len, &xferLen, 0);
        _CheckErr(ir, "libusb_bulk_transfer failed");
        if ((size_t)xferLen != len)
            throw RuntimeError("libusb_bulk_transfer short write (tried: %zu, got: %zu)", len, (size_t)xferLen);
    }
    
    struct libusb_device_descriptor getDeviceDescriptor() {
        struct libusb_device_descriptor desc;
        int ir = libusb_get_device_descriptor(_s.dev, &desc);
        _CheckErr(ir, "libusb_get_device_descriptor failed");
        return desc;
    }
    
    struct libusb_config_descriptor* getConfigDescriptor(uint8_t idx) {
        struct libusb_config_descriptor* desc;
        int ir = libusb_get_config_descriptor(_s.dev, 0, &desc);
        _CheckErr(ir, "libusb_config_descriptor failed");
        return desc;
    }
    
    operator bool() const { return _s.dev; }
    operator libusb_device*() const { return _s.dev; }
    operator libusb_device_handle*() const { return _s.devHandle; }
    
private:
    static void _CheckErr(int ir, const char* errMsg) {
        if (ir < 0) throw RuntimeError("%s: %s", errMsg, libusb_error_name(ir));
    }
    
    static libusb_context* _USBCtx() {
        static std::once_flag Once;
        static libusb_context* Ctx = nullptr;
        std::call_once(Once, [](){
            int ir = libusb_init(&Ctx);
            _CheckErr(ir, "libusb_init failed");
        });
        return Ctx;
    }
    
    void _setDev(libusb_device* dev) {
        if (dev) libusb_ref_device(dev);
        if (_s.dev) libusb_unref_device(_s.dev);
        _s.dev = dev;
    }
    
    void _reset() {
        close();
        _setDev(nullptr);
    }
    
    struct {
        libusb_device* dev = nullptr;
        libusb_device_handle* devHandle = nullptr;
    } _s = {};
};
