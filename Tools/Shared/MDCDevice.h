#pragma once
#include <cassert>
#include <chrono>
#include "Toastbox/USBDevice.h"
#include "STAppTypes.h"
#include "TimeInstant.h"
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
    
    void reset() {
        using namespace STApp;
        Cmd cmd = { .op = Op::Reset };
        _dev.vendorRequestOut(STApp::CtrlReqs::CmdExec, cmd);
        
        // Flush data from the endpoint until we get a ZLP
        for (;;) {
            const size_t len = _dev.read(STApp::Endpoints::DataIn, _buf, sizeof(_buf));
            if (!len) break;
        }
        
        // Read until we get the sentinel
        // It's possible to get a ZLP in this stage -- just ignore it
        for (;;) {
            uint8_t sentinel = 0;
            const uint8_t len = _dev.read(STApp::Endpoints::DataIn, &sentinel, sizeof(sentinel));
            if (len == sizeof(sentinel)) break;
        }
    }
    
    void ledSet(uint8_t idx, bool on) {
        using namespace STApp;
        Cmd cmd = {
            .op = Op::LEDSet,
            .arg = {
                .LEDSet = {
                    .idx = idx,
                    .on = on,
                },
            },
        };
        _dev.vendorRequestOut(STApp::CtrlReqs::CmdExec, cmd);
    }
    
    USBDevice& usbDevice() { return _dev; }
    
private:
    USBDevice _dev;
    uint8_t _buf[16*1024];
};
