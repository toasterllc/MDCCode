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
    _dev(std::move(dev)) {
//        _interface = interfaces[0];
////        cmdOutPipe = USBPipe(_interface, Endpoints::CmdOut);
////        cmdInPipe = USBPipe(_interface, Endpoints::CmdOut::CmdIn);
//        pixInPipe = USBPipe(_interface, Endpoints::CmdOut::PixIn);
    }
    
    void reset_dataStage0() {
        using namespace STApp;
        _dev.vendorRequestOut(STApp::CtrlReqs::ResetMeow, nullptr, 0);
        
        // Reset our pipes now that the device is reset
        for (const uint8_t ep : {Endpoints::DataIn}) {
            _dev.reset(ep);
        }
    }
    
    void reset_dataStage1() {
        using namespace STApp;
        Cmd cmd = { .op = Op::Reset };
        _dev.vendorRequestOut(STApp::CtrlReqs::CmdExec, cmd);
        
//        // Reset our pipes now that the device is reset
//        for (const uint8_t ep : {Endpoints::DataIn}) {
//            _dev.reset(ep);
//        }
    }
    
    void ledSet(uint8_t idx, bool on) {
        #warning TODO: implement
        abort();
//        using namespace STApp;
//        Cmd cmd = {
//            .op = Op::LEDSet,
//            .arg = {
//                .LEDSet = {
//                    .idx = idx,
//                    .on = on,
//                },
//            },
//        };
//        _dev.write(STApp::Endpoints::CmdOut, cmd);
//        _waitOrThrow("LEDSet command failed");
    }
    
    USBDevice& usbDevice() { return _dev; }
    
//    void pixReadImage(STApp::Pixel* pixels, size_t count, Milliseconds timeout=0) const {
//        pixInPipe.readBuf(pixels, count*sizeof(STApp::Pixel), timeout);
//    }
//    
//    USBPipe cmdOutPipe;
//    USBPipe cmdInPipe;
//    USBPipe pixInPipe;
    
private:
    USBDevice _dev;
    
    void _waitOrThrow(const char* errMsg) {
        #warning TODO: implement
        abort();
//        // Wait for completion and throw on failure
//        STApp::Status s = {};
//        _dev.read(STApp::Endpoints::DataIn, s);
//        if (s != STApp::Status::OK) throw std::runtime_error(errMsg);
    }
};
