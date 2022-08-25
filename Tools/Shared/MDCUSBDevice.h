#pragma once
#include <cassert>
#include <chrono>
#include "Lockable.h"
#include "Toastbox/USB.h"
#include "Toastbox/USBDevice.h"
#include "Toastbox/RuntimeError.h"
#include "Code/Shared/STM.h"
#include "Code/Shared/Img.h"
#include "Code/Shared/SD.h"
#include "Code/Shared/ImgSD.h"
#include "Code/Shared/ChecksumFletcher32.h"

class MDCUSBDevice {
public:
    using USBDevice = Toastbox::USBDevice;
    
    static bool USBDeviceMatches(const USBDevice& dev) {
        namespace USB = Toastbox::USB;
        USB::DeviceDescriptor desc = dev.deviceDescriptor();
        return desc.idVendor==1155 && desc.idProduct==57105;
    }
    
    static std::vector<MDCUSBDevice> GetDevices() {
        std::vector<MDCUSBDevice> devs;
        auto usbDevs = USBDevice::GetDevices();
        for (USBDevice& usbDev : usbDevs) {
            if (USBDeviceMatches(usbDev)) {
                try {
                    devs.push_back(std::move(usbDev));
                
                // Suppress failures to create a MDCUSBDevice
                } catch (const std::exception& e) {
                    printf("Failed to create MDCUSBDevice: %s\n", e.what());
                }
            }
        }
        return devs;
    }
    
    MDCUSBDevice(USBDevice&& dev) : _dev(std::move(dev)) {
        printf("[MDCUSBDevice] endpointsFlush START\n");
        // We don't know what state the device was left in, so flush the endpoints
        endpointsFlush();
        printf("[MDCUSBDevice] endpointsFlush END\n");
        
        _serial = _dev.serialNumber();
        const STM::Status status = statusGet();
        _mode = status.mode;
    }
    
    MDCUSBDevice(MDCUSBDevice&&) = default;
    
    bool operator==(const MDCUSBDevice& x) const {
        return _dev == x._dev;
    }
    
    USBDevice& dev() { return _dev; }
    
    // MARK: - Accessors
    
    const std::string& serial() const { return _serial; }
    
    // MARK: - Common Commands
    void endpointsFlush() {
        const STM::Cmd cmd = { .op = STM::Op::EndpointsFlush };
        // Send command
        _dev.vendorRequestOut(0, cmd);
        
        // Flush endpoints
        const std::vector<uint8_t> eps = _dev.endpoints();
        for (const uint8_t ep : eps) {
            _flushEndpoint(ep);
        }
        _checkStatus("EndpointsFlush command failed");
    }
    
    STM::Status statusGet() {
        const STM::Cmd cmd = { .op = STM::Op::StatusGet };
        _sendCmd(cmd);
        
        STM::Status status;
        _dev.read(STM::Endpoints::DataIn, status);
        if (status.magic != STM::Status::MagicNumber) {
            throw Toastbox::RuntimeError("invalid magic number (expected:0x%08jx got:0x%08jx)",
                (uintmax_t)STM::Status::MagicNumber, (uintmax_t)status.magic);
        }
        
        _checkStatus("StatusGet command failed");
        return status;
    }
    
    void bootloaderInvoke() {
        const STM::Cmd cmd = { .op = STM::Op::BootloaderInvoke };
        _sendCmd(cmd);
        _checkStatus("BootloaderInvoke command failed");
    }
    
    // bootloaderInvoke version that replaces `this` with the newly-enumerated USB device
//    void bootloaderInvoke() {
//        const STM::Cmd cmd = { .op = STM::Op::BootloaderInvoke };
//        _dev.vendorRequestOut(0, cmd);
//        _checkStatus("BootloaderInvoke command failed");
//        
//        // Wait for a new MDCUSBDevice that's not equal to `this` (ie the underlying USB
//        // device is different), but has the same serial number
//        TimeInstant startTime;
//        do {
//            std::vector<MDCUSBDevice> devs = GetDevices();
//            for (MDCUSBDevice& dev : devs) {
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
        const STM::Cmd cmd = {
            .op = STM::Op::LEDSet,
            .arg = {
                .LEDSet = {
                    .idx = idx,
                    .on = on,
                },
            },
        };
        _sendCmd(cmd);
        _checkStatus("LEDSet command failed");
    }
    
    // MARK: - STMLoader Commands
    void stmWrite(uintptr_t addr, const void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMLoader);
        
        if (addr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)addr);
        
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::STMWrite,
            .arg = {
                .STMWrite = {
                    .addr = (uint32_t)addr,
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Send data
        _dev.write(STM::Endpoints::DataOut, data, len);
        _checkStatus("STMWrite command failed");
    }
    
    void stmReset(uintptr_t entryPointAddr) {
        assert(_mode == STM::Status::Modes::STMLoader);
        
        if (entryPointAddr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)entryPointAddr);
        
        const STM::Cmd cmd = {
            .op = STM::Op::STMReset,
            .arg = {
                .STMReset = {
                    .entryPointAddr = (uint32_t)entryPointAddr,
                },
            },
        };
        _sendCmd(cmd);
        _checkStatus("STMReset command failed");
    }
    
    // MARK: - STMApp Commands
    void hostModeInit() {
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = { .op = STM::Op::HostModeInit };
        _sendCmd(cmd);
        _checkStatus("HostModeInit command failed");
    }
    
    void hostModeEnter(STM::Peripheral periph) {
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = {
            .op = STM::Op::HostModeEnter,
            .arg = {
                .HostModeEnter = {
                    .periph = periph,
                },
            },
        };
        _sendCmd(cmd);
        _checkStatus("HostModeEnter command failed");
    }
    
    void iceRAMWrite(const void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMApp);
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::ICERAMWrite,
            .arg = {
                .ICERAMWrite = {
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Send data
        _dev.write(STM::Endpoints::DataOut, data, len);
        _checkStatus("ICERAMWrite command failed");
    }
    
    void iceFlashRead(uintptr_t addr, void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMApp);
        
        if (addr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)addr);
        
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::ICEFlashRead,
            .arg = {
                .ICEFlashRead = {
                    .addr = (uint32_t)addr,
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Read data
        _dev.read(STM::Endpoints::DataIn, data, len);
        _checkStatus("ICEFlashRead command failed");
    }
    
    void iceFlashWrite(uintptr_t addr, const void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMApp);
        
        if (addr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)addr);
        
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::ICEFlashWrite,
            .arg = {
                .ICEFlashWrite = {
                    .addr = (uint32_t)addr,
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Send data
        _dev.write(STM::Endpoints::DataOut, data, len);
        _checkStatus("ICEFlashWrite command failed");
    }
    
    void mspConnect() {
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = { .op = STM::Op::MSPConnect };
        _sendCmd(cmd);
        _checkStatus("MSPConnect command failed");
    }
    
    void mspDisconnect() {
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = { .op = STM::Op::MSPDisconnect };
        _sendCmd(cmd);
        _checkStatus("MSPDisconnect command failed");
    }
    
    void mspRead(uintptr_t addr, void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMApp);
        
        if (addr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)addr);
        
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::MSPRead,
            .arg = {
                .MSPRead = {
                    .addr = (uint32_t)addr,
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Read data
        _dev.read(STM::Endpoints::DataIn, data, len);
        _checkStatus("MSPRead command failed");
    }
    
    void mspWrite(uintptr_t addr, const void* data, size_t len) {
        assert(_mode == STM::Status::Modes::STMApp);
        
        if (addr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)addr);
        
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::MSPWrite,
            .arg = {
                .MSPWrite = {
                    .addr = (uint32_t)addr,
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Send data
        _dev.write(STM::Endpoints::DataOut, data, len);
        _checkStatus("MSPWrite command failed");
    }
    
    void mspDebug(const STM::MSPDebugCmd* cmds, size_t cmdsLen, void* resp, size_t respLen) {
        assert(_mode == STM::Status::Modes::STMApp);
        
        if (cmdsLen >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)cmdsLen);
        
        if (respLen >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)respLen);
        
        const STM::Cmd cmd = {
            .op = STM::Op::MSPDebug,
            .arg = {
                .MSPDebug = {
                    .cmdsLen = (uint32_t)cmdsLen,
                    .respLen = (uint32_t)respLen,
                },
            },
        };
        _sendCmd(cmd);
        
        // Write the MSPDebugCmds
        if (cmdsLen) {
            _dev.write(STM::Endpoints::DataOut, cmds, cmdsLen*sizeof(STM::MSPDebugCmd));
        }
        
        // Read back the queued data
        if (respLen) {
            _dev.read(STM::Endpoints::DataIn, resp, respLen);
        }
        
        _checkStatus("MSPDebug command failed");
    }
    
    STM::SDCardInfo sdCardInfo() {
        assert(_mode == STM::Status::Modes::STMApp);
        
        const STM::Cmd cmd = { .op = STM::Op::SDCardInfo };
        _sendCmd(cmd);
        
        STM::SDCardInfo cardInfo = {};
        _dev.read(STM::Endpoints::DataIn, cardInfo);
        return cardInfo;
    }
    
    void sdRead(SD::BlockIdx blockIdx) {
        assert(_mode == STM::Status::Modes::STMApp);
        
        const STM::Cmd cmd = {
            .op = STM::Op::SDRead,
            .arg = {
                .SDRead = {
                    .blockIdx = blockIdx,
                },
            },
        };
        _sendCmd(cmd);
        _checkStatus("SDRead command failed");
    }
    
    struct ImgExposure {
        uint16_t coarseIntTime  = 0;
        uint16_t fineIntTime    = 0;
        uint16_t analogGain     = 0;
    };
    
    void imgExposureSet(const ImgExposure& exp) {
        assert(_mode == STM::Status::Modes::STMApp);
        const STM::Cmd cmd = {
            .op = STM::Op::ImgExposureSet,
            .arg = {
                .ImgExposureSet = {
                    .coarseIntTime  = exp.coarseIntTime,
                    .fineIntTime    = exp.fineIntTime,
                    .analogGain     = exp.analogGain,
                },
            },
        };
        _sendCmd(cmd);
        _checkStatus("ImgExposureSet command failed");
    }
    
    STM::ImgCaptureStats imgCapture(uint8_t dstBlock, uint8_t skipCount) {
        assert(_mode == STM::Status::Modes::STMApp);
        
        const STM::Cmd cmd = {
            .op = STM::Op::ImgCapture,
            .arg = {
                .ImgCapture = {
                    .dstBlock = 0,
                    .skipCount = skipCount,
                },
            },
        };
        
        _sendCmd(cmd);
        
        STM::ImgCaptureStats stats;
        _dev.read(STM::Endpoints::DataIn, stats);
        _checkStatus("ImgCapture command failed");
        return stats;
    }
    
    std::unique_ptr<uint8_t[]> imgReadout() {
        assert(_mode == STM::Status::Modes::STMApp);
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(ImgSD::ImgPaddedLen);
        const size_t lenGot = _dev.read(STM::Endpoints::DataIn, buf.get(), ImgSD::ImgPaddedLen);
        if (lenGot < Img::Len) {
            throw Toastbox::RuntimeError("expected 0x%jx bytes, got 0x%jx bytes", (uintmax_t)ImgSD::ImgPaddedLen, (uintmax_t)lenGot);
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
    
    void readout(void* dst, size_t len) {
        assert(_mode == STM::Status::Modes::STMApp);
        if (!len) return; // Short-circuit if there's no data to read
        
        const size_t mps = _dev.maxPacketSize(STM::Endpoints::DataIn);
        if (len % mps) {
            throw Toastbox::RuntimeError("len isn't a multiple of max packet size (len: %ju, max packet size: %ju)", (uintmax_t)len, (uintmax_t)mps);
        }
        
        _dev.read(STM::Endpoints::DataIn, dst, len);
        
//        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(Img::PaddedLen);
//        const size_t lenGot = _dev.read(STM::Endpoints::DataIn, buf.get(), Img::PaddedLen);
//        if (lenGot < Img::Len) {
//            throw Toastbox::RuntimeError("expected 0x%jx bytes, got 0x%jx bytes", (uintmax_t)Img::PaddedLen, (uintmax_t)lenGot);
//        }
//        
//        // Validate checksum
//        const uint32_t checksumExpected = ChecksumFletcher32(buf.get(), Img::ChecksumOffset);
//        uint32_t checksumGot = 0;
//        memcpy(&checksumGot, (uint8_t*)buf.get()+Img::ChecksumOffset, Img::ChecksumLen);
//        if (checksumGot != checksumExpected) {
//            throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
//        }
//        
//        return buf;
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
    
    void _sendCmd(const STM::Cmd& cmd) {
        _dev.vendorRequestOut(0, cmd);
        _checkStatus("command rejected");
    }
    
    void _checkStatus(const char* errMsg) {
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

using MDCUSBDevicePtr = std::shared_ptr<MDCTools::Lockable<MDCUSBDevice>>;
