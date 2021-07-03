#pragma once
#include "USBDevice.h"
#include "USBInterface.h"
#include "USBPipe.h"
#include "SendRight.h"
#include "STLoaderTypes.h"

class MDCLoaderDevice : public USBDevice {
public:
    static NSDictionary* MatchingDictionary() {
        return USBDevice::MatchingDictionary(1155, 57105);
    }
    
    static std::vector<MDCLoaderDevice> FindDevice() {
        return USBDevice::FindDevice<MDCLoaderDevice>(MatchingDictionary());
    }
    
    // Default constructor: empty
    MDCLoaderDevice() {}
    
    MDCLoaderDevice(SendRight&& service) :
    USBDevice(std::move(service)) {
        std::vector<USBInterface> interfaces = usbInterfaces();
        if (interfaces.size() != 1) throw std::runtime_error("invalid number of USB interfaces");
        _interface = interfaces[0];
        
        cmdOutPipe = USBPipe(_interface, STLoader::EndpointIdxs::CmdOut);
        dataOutPipe = USBPipe(_interface, STLoader::EndpointIdxs::DataOut);
        dataInPipe = USBPipe(_interface, STLoader::EndpointIdxs::DataIn);
    }
    
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
        cmdOutPipe.write(cmd);
        // Send data
        dataOutPipe.writeBuf(data, len);
        _waitOrError("STWrite command failed");
    }
    
    void stFinish(uint32_t entryPointAddr) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::STFinish,
            .arg = {
                .STFinish = {
                    .entryPointAddr = entryPointAddr,
                },
            },
        };
        
        cmdOutPipe.write(cmd);
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
        cmdOutPipe.write(cmd);
        // Send data
        dataOutPipe.writeBuf(data, len);
        _waitOrError("ICEWrite command failed");
    }
    
    void mspStart() {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPStart,
        };
        // Send command
        cmdOutPipe.write(cmd);
        _waitOrError("MSPStart command failed");
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
        cmdOutPipe.write(cmd);
        // Send data
        dataOutPipe.writeBuf(data, len);
        _waitOrError("MSPWrite command failed");
    }
    
    void mspFinish() {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPFinish,
        };
        // Send command
        cmdOutPipe.write(cmd);
        _waitOrError("MSPFinish command failed");
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
        cmdOutPipe.write(cmd);
        _waitOrError("LEDSet command failed");
    }
    
    USBPipe cmdOutPipe;
    USBPipe dataOutPipe;
    USBPipe dataInPipe;
    
private:
    USBInterface _interface;
    
    void _waitOrError(const char* errMsg) {
        // Wait for completion and throw on failure
        STLoader::Status s;
        dataInPipe.read(s);
        if (s != STLoader::Status::OK) throw std::runtime_error(errMsg);
    }
};
