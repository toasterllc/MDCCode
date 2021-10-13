#pragma once
#include "Toastbox/USBDevice.h"
#include "STM.h"

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
    
    void resetEndpoints() {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::ResetEndpoints,
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        // Flush endpoints
        _flushEndpoint(Endpoints::DataOut);
        _flushEndpoint(Endpoints::DataIn);
        _waitOrThrow("ResetEndpoints command failed");
    }
    
    void ledSet(uint8_t idx, bool on) {
        using namespace STM;
        Cmd cmd = {
            .op = Op::LEDSet,
            .arg = {
                .LEDSet = {
                    .idx = idx,
                    .on = on,
                },
            },
        };
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("LEDSet command failed");
    }
    
    void stmWrite(uint32_t addr, const void* data, size_t len) {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::STMWrite,
            .arg = {
                .STMWrite = {
                    .addr = addr,
                    .len = (uint32_t)len,
                },
            },
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        // Send data
        _dev.write(Endpoints::DataOut, data, len);
        _waitOrThrow("STMWrite command failed");
    }
    
    void stmReset(uint32_t entryPointAddr) {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::STMReset,
            .arg = {
                .STMReset = {
                    .entryPointAddr = entryPointAddr,
                },
            },
        };
        _dev.vendorRequestOut(0, cmd);
    }
    
    void iceWrite(const void* data, size_t len) {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::ICEWrite,
            .arg = {
                .ICEWrite = {
                    .len = (uint32_t)len,
                },
            },
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        // Send data
        _dev.write(Endpoints::DataOut, data, len);
        _waitOrThrow("ICEWrite command failed");
    }
    
    void mspConnect() {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::MSPConnect,
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("MSPConnect command failed");
    }
    
    void mspDisconnect() {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::MSPDisconnect,
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("MSPDisconnect command failed");
    }
    
    void mspWrite(uint32_t addr, const void* data, size_t len) {
        using namespace STM;
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
        _dev.vendorRequestOut(0, cmd);
        // Send data
        _dev.write(Endpoints::DataOut, data, len);
        _waitOrThrow("MSPWrite command failed");
    }
    
    void mspRead(uint32_t addr, void* data, size_t len) {
        using namespace STM;
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
        _dev.vendorRequestOut(0, cmd);
        // Read data
        _dev.read(Endpoints::DataIn, data, len);
        _waitOrThrow("MSPRead command failed");
    }
    
    void mspDebug(const STM::MSPDebugCmd* cmds, size_t cmdsLen, void* resp, size_t respLen) {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::MSPDebug,
            .arg = {
                .MSPDebug = {
                    .cmdsLen = (uint32_t)cmdsLen,
                    .respLen = (uint32_t)respLen,
                },
            },
        };
        
        // Send command
        _dev.vendorRequestOut(0, cmd);
        
        // Write the MSPDebugCmds
        if (cmdsLen) {
            _dev.write(Endpoints::DataOut, cmds, cmdsLen*sizeof(MSPDebugCmd));
        }
        
        // Read back the queued data
        if (respLen) {
            _dev.read(Endpoints::DataIn, resp, respLen);
        }
        
        _waitOrThrow("MSPDebug command failed");
    }
    
private:
    void _flushEndpoint(uint8_t ep) {
        if ((ep&USB::Endpoint::DirectionMask) == USB::Endpoint::DirectionOut) {
            // Send 2x ZLPs + sentinel
            _dev.write(ep, nullptr, 0);
            _dev.write(ep, nullptr, 0);
            const uint8_t sentinel = 0;
            _dev.write(ep, &sentinel, sizeof(sentinel));
        
        } else {
            // Flush data from the endpoint until we get a ZLP
            for (;;) {
                const size_t len = _dev.read(ep, _buf, sizeof(_buf));
                if (!len) break;
            }
            
            // Read until we get the sentinel
            // It's possible to get a ZLP in this stage -- just ignore it
            for (;;) {
                uint8_t sentinel = 0;
                const size_t len = _dev.read(ep, &sentinel, sizeof(sentinel));
                if (len == sizeof(sentinel)) break;
            }
        }
    }
    
    void _waitOrThrow(const char* errMsg) {
        using namespace STM;
        // Wait for completion and throw on failure
        bool s = false;
        _dev.read(Endpoints::DataIn, s);
        if (!s) throw std::runtime_error(errMsg);
    }
    
    USBDevice _dev;
    uint8_t _buf[16*1024];
};
