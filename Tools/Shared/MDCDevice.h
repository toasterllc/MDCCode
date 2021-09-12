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
        
        // Reset our pipes now that the device is reset
        for (const uint8_t ep : {Endpoints::DataIn}) {
            _dev.reset(ep);
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
};
