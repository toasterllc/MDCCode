#pragma once
#include <cassert>
#include <chrono>
#include "Toastbox/USB.h"
#include "Toastbox/USBDevice.h"
#include "Toastbox/RuntimeError.h"
#include "STM.h"
#include "Img.h"
#include "ChecksumFletcher32.h"
#include "TimeInstant.h"

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
                try {
                    devs.push_back(std::move(usbDev));
                
                // Suppress failures to create a MDCDevice
                } catch (...) {}
            }
        }
        return devs;
    }
    
    MDCDevice(USBDevice&& dev) : _dev(std::move(dev)) {
        // We don't know what state the device was left in, so flush the endpoints
        endpointsFlush();
        
        _serial = _dev.serialNumber();
        const STM::Status status = statusGet();
        _mode = status.mode;
    }
    
    bool operator==(const MDCDevice& x) const {
        return _dev == x._dev;
    }
    
    USBDevice& usbDevice() { return _dev; }
    
    #pragma mark - Accessors
    
    const std::string& serial() const { return _serial; }
    
    #pragma mark - Common Commands
    void endpointsFlush() {
        const STM::Cmd cmd = { .op = STM::Op::EndpointsFlush };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        
        // Flush endpoints
        const std::vector<uint8_t> eps = _dev.endpoints();
        for (const uint8_t ep : eps) {
            _flushEndpoint(ep);
        }
        _waitOrThrow("EndpointsFlush command failed");
    }
    
    STM::Status statusGet() {
        const STM::Cmd cmd = { .op = STM::Op::StatusGet };
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("StatusGet command failed");
        
        STM::Status status;
        _dev.read(STM::Endpoints::DataIn, status);
        if (status.magic != STM::Status::MagicNumber) {
            throw Toastbox::RuntimeError("invalid magic number (expected:0x%08jx got:0x%08jx)",
                (uintmax_t)STM::Status::MagicNumber, (uintmax_t)status.magic);
        }
        return status;
    }
    
    void bootloaderInvoke() {
        const STM::Cmd cmd = { .op = STM::Op::BootloaderInvoke };
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("BootloaderInvoke command failed");
    }
    
    // bootloaderInvoke version that replaces `this` with the newly-enumerated USB device
//    void bootloaderInvoke() {
//        const STM::Cmd cmd = { .op = STM::Op::BootloaderInvoke };
//        _dev.vendorRequestOut(0, cmd);
//        _waitOrThrow("BootloaderInvoke command failed");
//        
//        // Wait for a new MDCDevice that's not equal to `this` (ie the underlying USB
//        // device is different), but has the same serial number
//        TimeInstant startTime;
//        do {
//            std::vector<MDCDevice> devs = GetDevices();
//            for (MDCDevice& dev : devs) {
//                if (dev == *this) continue;
//                if (_serial == dev.serial()) {
//                    *this = std::move(dev);
//                    return;
//                }
//            }
//        } while (startTime.durationMs() < 5000);
//        
//        throw Toastbox::RuntimeError("timeout waiting for device to re-enumerate");
//    }
    
    void ledSet(uint8_t idx, bool on) {
        STM::Cmd cmd = {
            .op = STM::Op::LEDSet,
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
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::STMWrite,
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
        _dev.write(STM::Endpoints::DataOut, data, len);
        _waitOrThrow("STMWrite DataOut failed");
    }
    
    void stmReset(uint32_t entryPointAddr) {
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::STMReset,
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
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::ICEWrite,
            .arg = {
                .ICEWrite = {
                    .len = (uint32_t)len,
                },
            },
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        // Send data
        _dev.write(STM::Endpoints::DataOut, data, len);
        _waitOrThrow("ICEWrite command failed");
    }
    
    void mspConnect() {
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::MSPConnect,
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("MSPConnect command failed");
    }
    
    void mspDisconnect() {
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::MSPDisconnect,
        };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("MSPDisconnect command failed");
    }
    
    void mspWrite(uint32_t addr, const void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::MSPWrite,
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
        _dev.write(STM::Endpoints::DataOut, data, len);
        _waitOrThrow("MSPWrite command failed");
    }
    
    void mspRead(uint32_t addr, void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::MSPRead,
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
        _dev.read(STM::Endpoints::DataIn, data, len);
        _waitOrThrow("MSPRead command failed");
    }
    
    void mspDebug(const STM::MSPDebugCmd* cmds, size_t cmdsLen, void* resp, size_t respLen) {
        assert(_mode == STM::Status::Modes::STMLoader);
        const STM::Cmd cmd = {
            .op = STM::Op::MSPDebug,
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
            _dev.write(STM::Endpoints::DataOut, cmds, cmdsLen*sizeof(STM::MSPDebugCmd));
        }
        
        // Read back the queued data
        if (respLen) {
            _dev.read(STM::Endpoints::DataIn, resp, respLen);
        }
        
        _waitOrThrow("MSPDebug DataOut/DataIn command failed");
    }
    
    #pragma mark - STMApp Commands
    void sdRead(uint32_t addr) {
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = {
            .op = STM::Op::SDRead,
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
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = { .op = STM::Op::ImgCapture };
        _dev.vendorRequestOut(0, cmd);
        _waitOrThrow("ImgCapture command failed");
        
        STM::ImgCaptureStats stats;
        _dev.read(STM::Endpoints::DataIn, stats);
        return stats;
    }
    
    void imgSetExposure(uint16_t coarseIntTime, uint16_t fineIntTime, uint16_t gain) {
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = {
            .op = STM::Op::ImgSetExposure,
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
        assert(_mode == STM::Status::Modes::STMApp);
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(Img::PaddedLen);
        const size_t lenGot = _dev.read(STM::Endpoints::DataIn, buf.get(), Img::PaddedLen);
        if (lenGot < Img::Len) {
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
        // Wait for completion and throw on failure
        bool s = false;
        _dev.read(STM::Endpoints::DataIn, s);
        if (!s) throw std::runtime_error(errMsg);
    }
    
    USBDevice _dev;
    std::string _serial = {};
    STM::Status::Mode _mode = STM::Status::Modes::None;
    uint8_t _buf[16*1024];
};
