#pragma once
#include "Toastbox/USBDevice.h"
#include "STLoaderTypes.h"

class MDCLoaderDevice {
public:
    static std::vector<MDCLoaderDevice> GetDevices() {
        std::vector<MDCLoaderDevice> devs;
        auto usbDevs = USBDevice::GetDevices();
        for (USBDevice& usbDev : usbDevs) {
            USB::DeviceDescriptor desc = usbDev.deviceDescriptor();
            if (desc.idVendor==1155 && desc.idProduct==57105) {
                devs.emplace_back(std::move(usbDev));
            }
        }
        return devs;
    }
    
    MDCLoaderDevice(USBDevice&& dev) : _dev(std::move(dev)) {}
    
    void stWrite(uint32_t addr, const void* data, size_t len) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::STWrite,
            .arg = {
                .STWrite = {
                    .addr = addr,
                    .len = (uint32_t)len,
                },
            },
        };
        // Send command
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
        // Send data
        _dev.write(STLoader::Endpoints::DataOut, data, len);
        _waitOrThrow("STWrite command failed");
    }
    
    void stReset(uint32_t entryPointAddr) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::STReset,
            .arg = {
                .STReset = {
                    .entryPointAddr = entryPointAddr,
                },
            },
        };
        
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
    }
    
    void iceWrite(const void* data, size_t len) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::ICEWrite,
            .arg = {
                .ICEWrite = {
                    .len = (uint32_t)len,
                },
            },
        };
        // Send command
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
        // Send data
        _dev.write(STLoader::Endpoints::DataOut, data, len);
        _waitOrThrow("ICEWrite command failed");
    }
    
    void mspConnect() {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPConnect,
        };
        // Send command
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
        _waitOrThrow("MSPStart command failed");
    }
    
    void mspDisconnect() {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPDisconnect,
        };
        // Send command
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
        _waitOrThrow("MSPFinish command failed");
    }
    
    void mspWrite(uint32_t addr, const void* data, size_t len) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPWrite,
            .arg = {
                .MSPWrite = {
                    .addr = addr,
                    .len = (uint32_t)len,
                },
            },
        };
        // Send command
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
        // Send data
        _dev.write(STLoader::Endpoints::DataOut, data, len);
        _waitOrThrow("MSPWrite command failed");
    }
    
    void mspRead(uint32_t addr, void* data, size_t len) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPRead,
            .arg = {
                .MSPRead = {
                    .addr = addr,
                    .len = (uint32_t)len,
                },
            },
        };
        // Send command
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
        // Read data
        _dev.read(STLoader::Endpoints::DataIn, data, len);
        _waitOrThrow("MSPRead command failed");
    }
    
    void ledSet(uint8_t idx, bool on) {
        using namespace STLoader;
        Cmd cmd = {
            .op = Op::LEDSet,
            .arg = {
                .LEDSet = {
                    .idx = idx,
                    .on = on,
                },
            },
        };
        _dev.write(STLoader::Endpoints::CmdOut, cmd);
        _waitOrThrow("LEDSet command failed");
    }
    
private:
    USBDevice _dev;
    
    void _waitOrThrow(const char* errMsg) {
        // Wait for completion and throw on failure
        STLoader::Status s = {};
        _dev.read(STLoader::Endpoints::DataIn, s);
        if (s != STLoader::Status::OK) throw std::runtime_error(errMsg);
    }
};
