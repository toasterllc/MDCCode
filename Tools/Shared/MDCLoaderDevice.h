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
        statusInPipe = USBPipe(_interface, STLoader::EndpointIdxs::StatusIn);
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
    }
    
    STLoader::Status statusGet() {
        using namespace STLoader;
        // Request status
        const Cmd cmd = { .op = Op::StatusGet };
        cmdOutPipe.write(cmd);
        // Read status
        Status status;
        statusInPipe.read(status);
        return status;
    }
    
    STLoader::Status stWrite(uint32_t addr, const void* data, size_t len) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::STWrite,
            .arg = {
                .STWrite = {
                    .addr = addr,
                },
            },
        };
        // Send command
        cmdOutPipe.write(cmd);
        // Send data
        dataOutPipe.writeBuf(data, len);
        // Wait for write to complete and return status
        for (;;) {
            const STLoader::Status s = statusGet();
            if (s != STLoader::Status::Busy) return s;
        }
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
        
        cmdOutPipe.write(cmd);
    }
    
    STLoader::Status iceWrite(const void* data, size_t len) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::ICEWrite,
        };
        // Send command
        cmdOutPipe.write(cmd);
        // Send data
        dataOutPipe.writeBuf(data, len);
        // Signal end-of-data
        dataOutPipe.writeBuf(nullptr, 0);
        // Wait for write to complete and return status
        for (;;) {
            const STLoader::Status s = statusGet();
            if (s != STLoader::Status::Busy) return s;
        }
    }
    
    STLoader::Status mspWrite(uint32_t addr, const void* data, size_t len) {
        using namespace STLoader;
        const Cmd cmd = {
            .op = Op::MSPWrite,
            .arg = {
                .MSPWrite = {
                    .addr = addr,
                },
            },
        };
        // Send command
        cmdOutPipe.write(cmd);
        // Send data
        dataOutPipe.writeBuf(data, len);
        // Signal end-of-data
        dataOutPipe.writeBuf(nullptr, 0);
        // Wait for write to complete and return status
        for (;;) {
            const STLoader::Status s = statusGet();
            if (s != STLoader::Status::Busy) return s;
        }
    }
    
    USBPipe cmdOutPipe;
    USBPipe dataOutPipe;
    USBPipe statusInPipe;
    
private:
    USBInterface _interface;
};
