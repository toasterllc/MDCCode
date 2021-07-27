#pragma once
#include "USBDevice.h"
#include "SendRight.h"
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
    
    MDCLoaderDevice(USBDevice&& dev) :
    _dev(std::move(dev)),
    _cmdOutPipe(_dev.getInterface(0).getPipe(STLoader::Endpoints::CmdOut)),
    _dataOutPipe(_dev.getInterface(0).getPipe(STLoader::Endpoints::DataOut)),
    _dataInPipe(_dev.getInterface(0).getPipe(STLoader::Endpoints::DataIn)) {}
    
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
        _cmdOutPipe.write(cmd);
        // Send data
        _dataOutPipe.write(data, len);
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
        
        _cmdOutPipe.write(cmd);
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
        _cmdOutPipe.write(cmd);
        // Send data
        _dataOutPipe.write(data, len);
        _waitOrThrow("ICEWrite command failed");
    }
    
    void mspConnect() {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPConnect,
        };
        // Send command
        _cmdOutPipe.write(cmd);
        _waitOrThrow("MSPStart command failed");
    }
    
    void mspDisconnect() {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPDisconnect,
        };
        // Send command
        _cmdOutPipe.write(cmd);
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
        _cmdOutPipe.write(cmd);
        // Send data
        _dataOutPipe.write(data, len);
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
        _cmdOutPipe.write(cmd);
        // Read data
        _dataInPipe.read(data, len);
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
        _cmdOutPipe.write(cmd);
        _waitOrThrow("LEDSet command failed");
    }
    
private:
    USBDevice _dev;
    const USBDevice::Pipe& _cmdOutPipe;
    const USBDevice::Pipe& _dataOutPipe;
    const USBDevice::Pipe& _dataInPipe;
    
    void _waitOrThrow(const char* errMsg) {
        // Wait for completion and throw on failure
        STLoader::Status s;
        _dataInPipe.read(s);
        if (s != STLoader::Status::OK) throw std::runtime_error(errMsg);
    }
};
