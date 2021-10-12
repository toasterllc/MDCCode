#pragma once
#include <cassert>
#include <chrono>
#include "Toastbox/USBDevice.h"
#include "STAppTypes.h"
using namespace std::chrono;

class MDCDevice {
public:
    static std::vector<MDCDevice> GetDevices() {
        std::vector<MDCDevice> devs;
        auto usbDevs = USBDevice::GetDevices();
        for (USBDevice& usbDev : usbDevs) {
            USB::DeviceDescriptor desc = usbDev.deviceDescriptor();
            if (desc.idVendor==1155 && desc.idProduct==57105) {
                devs.emplace_back(std::move(usbDev));
            }
        }
        return devs;
    }
    
    MDCDevice(USBDevice&& dev) :
    _dev(std::move(dev)) {}
    
    void resetEndpoints() {
        using namespace STApp;
        const Cmd cmd = { .op = Op::ResetEndpoints };
        _dev.vendorRequestOut(0, cmd);
        _flushEndpoint(Endpoints::DataIn);
    }
    
    void bootloader() {
        using namespace STApp;
        const Cmd cmd = { .op = Op::Bootloader };
        _dev.vendorRequestOut(0, cmd);
    }
    
    void sdRead(uint32_t addr) {
        using namespace STApp;
        const Cmd cmd = {
            .op = Op::SDRead,
            .arg = {
                .SDRead = {
                    .addr = addr,
                },
            },
        };
        _dev.vendorRequestOut(0, cmd);
        _flushEndpoint(Endpoints::DataIn);
    }
    
    void imgSetExposure(uint16_t coarseIntTime, uint16_t fineIntTime, uint16_t gain) {
        using namespace STApp;
        const Cmd cmd = {
            .op = Op::ImgSetExposure,
            .arg = {
                .ImgSetExposure = {
                    .coarseIntTime  = coarseIntTime,
                    .fineIntTime    = fineIntTime,
                    .gain           = gain,
                },
            },
        };
        _dev.vendorRequestOut(0, cmd);
    }
    
    void imgCapture() {
        using namespace STApp;
        const Cmd cmd = { .op = Op::ImgCapture };
        _dev.vendorRequestOut(0, cmd);
    }
    
    void ledSet(uint8_t idx, bool on) {
        using namespace STApp;
        const Cmd cmd = {
            .op = Op::LEDSet,
            .arg = {
                .LEDSet = {
                    .idx = idx,
                    .on = on,
                },
            },
        };
        _dev.vendorRequestOut(0, cmd);
    }
    
    USBDevice& usbDevice() { return _dev; }
    
private:
    void _flushEndpoint(uint8_t ep) {
        if (ep & USB::Endpoint::DirectionIn) {
            // Flush data from the endpoint until we get a ZLP
            for (;;) {
                const size_t len = _dev.read(ep, _buf, sizeof(_buf));
                if (!len) break;
            }
            
            // Read until we get the sentinel
            // It's possible to get a ZLP in this stage -- just ignore it
            for (;;) {
                uint8_t sentinel = 0;
                const uint8_t len = _dev.read(ep, &sentinel, sizeof(sentinel));
                if (len == sizeof(sentinel)) break;
            }
        
        } else {
            // Send 2x ZLPs + sentinel
            _dev.write(ep, nullptr, 0);
            _dev.write(ep, nullptr, 0);
            const uint8_t sentinel = 0;
            _dev.write(ep, &sentinel, sizeof(sentinel));
        }
    }
    
    USBDevice _dev;
    uint8_t _buf[16*1024];
};
