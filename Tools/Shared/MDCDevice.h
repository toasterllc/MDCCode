#pragma once
#include <cassert>
#include <chrono>
#include "Toastbox/USB.h"
#include "Toastbox/USBDevice.h"
#include "Toastbox/RuntimeError.h"
#include "STM.h"
#include "Img.h"
#include "ChecksumFletcher32.h"

class MDCDevice {
public:
    using USBDevice = Toastbox::USBDevice;
    
    static bool USBDeviceMatches(const USBDevice& dev) {
        namespace USB = Toastbox::USB;
        USB::DeviceDescriptor desc = dev.deviceDescriptor();
        return desc.idVendor==1155 && desc.idProduct==57105;
    }
    
    static std::vector<MDCDevice> GetDevices() {
        std::vector<MDCDevice> devs;
        auto usbDevs = USBDevice::GetDevices();
        for (USBDevice& usbDev : usbDevs) {
            if (USBDeviceMatches(usbDev)) {
                devs.emplace_back(std::move(usbDev));
            }
        }
        return devs;
    }
    
    MDCDevice(USBDevice&& dev) :
    _dev(std::move(dev)) {}
    
    USBDevice& usbDevice() { return _dev; }
    
    #pragma mark - Common Commands
    void flushEndpoints() {
        using namespace STM;
        const Cmd cmd = { .op = Op::FlushEndpoints };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        
        // Flush endpoints
        const std::vector<uint8_t> eps = _dev.endpoints();
        for (const uint8_t ep : eps) {
            _flushEndpoint(ep);
        }
        _waitOrThrow("FlushEndpoints command failed");
    }
    
    void invokeBootloader() {
        using namespace STM;
        const Cmd cmd = { .op = Op::InvokeBootloader };
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("InvokeBootloader command failed");
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
    
    #pragma mark - STMLoader Commands
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
        // Check preliminary status
        _waitOrThrow("STMWrite command failed");
        // Send data
        _dev.write(Endpoints::DataOut, data, len);
        _waitOrThrow("STMWrite DataOut failed");
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
        _waitOrThrow("STMReset command failed");
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
        // Check preliminary status
        _waitOrThrow("MSPDebug command failed");
        
        // Write the MSPDebugCmds
        if (cmdsLen) {
            _dev.write(Endpoints::DataOut, cmds, cmdsLen*sizeof(MSPDebugCmd));
        }
        
        // Read back the queued data
        if (respLen) {
            _dev.read(Endpoints::DataIn, resp, respLen);
        }
        
        _waitOrThrow("MSPDebug DataOut/DataIn command failed");
    }
    
    #pragma mark - STMApp Commands
    void sdRead(uint32_t addr) {
        using namespace STM;
        const Cmd cmd = {
            .op = Op::SDRead,
            .arg = {
                .SDRead = {
                    .addr = addr,
                },
            },
        };
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("SDRead command failed");
    }
    
    STM::ImgCaptureStats imgCapture() {
        using namespace STM;
        const Cmd cmd = { .op = Op::ImgCapture };
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("ImgCapture command failed");
        
        ImgCaptureStats stats;
        _dev.read(Endpoints::DataIn, stats);
        return stats;
    }
    
    void imgSetExposure(uint16_t coarseIntTime, uint16_t fineIntTime, uint16_t gain) {
        using namespace STM;
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
        _waitOrThrow("ImgSetExposure command failed");
    }
    
    std::unique_ptr<uint8_t[]> imgReadout() {
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(Img::PaddedLen);
        const size_t lenGot = _dev.read(STM::Endpoints::DataIn, buf.get(), Img::PaddedLen);
        if (lenGot != Img::PaddedLen) {
            throw Toastbox::RuntimeError("expected 0x%jx bytes, got 0x%jx bytes", (uintmax_t)Img::PaddedLen, (uintmax_t)lenGot);
        }
        
        // Validate checksum
        const uint32_t checksumExpected = ChecksumFletcher32(buf.get(), Img::ChecksumOffset);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, (uint8_t*)buf.get()+Img::ChecksumOffset, Img::ChecksumLen);
        if (checksumGot != checksumExpected) {
            throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
        }
        
        return buf;
    }
    
private:
    void _flushEndpoint(uint8_t ep) {
        namespace USB = Toastbox::USB;
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
