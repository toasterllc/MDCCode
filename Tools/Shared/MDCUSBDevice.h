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
        printf("[MDCUSBDevice] reset START\n");
        // We don't know what state the device was left in, so reset its state
        reset();
        printf("[MDCUSBDevice] reset END\n");
        
        _serial = _dev.serialNumber();
        const STM::Status status = statusGet();
        _mode = status.mode;
    }
    
    // Copy
    MDCUSBDevice(const MDCUSBDevice& x) = delete;
    MDCUSBDevice& operator=(const MDCUSBDevice& x) = delete;
    // Move
    MDCUSBDevice(MDCUSBDevice&& x) = default;
    MDCUSBDevice& operator=(MDCUSBDevice&& x) = default;
    
    bool operator==(const MDCUSBDevice& x) const {
        return _dev == x._dev;
    }
    
    const USBDevice& dev() const { return _dev; }
    
    // MARK: - Accessors
    
    const std::string& serial() const { return _serial; }
    
    // MARK: - Common Commands
    void reset() {
        // Send Reset command
        // We're not using _sendCmd() because the Reset command is special and doesn't respond with the typical
        // 'command-accepted' status on the DataIn endpoint, which _sendCmd() expects. (The Reset command
        // doesn't send this status because the state of endpoint is assumed broken hence the need to reset.)
        const STM::Cmd cmd = { .op = STM::Op::Reset };
        _dev.vendorRequestOut(0, cmd);
        
        // Reset endpoints
        const std::vector<uint8_t> eps = _dev.endpoints();
        for (const uint8_t ep : eps) {
            _endpointReset(ep);
        }
        _checkStatus("Reset command failed");
    }
    
    STM::Status statusGet() {
        const STM::Cmd cmd = { .op = STM::Op::StatusGet };
        _sendCmd(cmd);
        
        STM::Status status;
        _dev.read(STM::Endpoint::DataIn, status);
        if (status.magic != STM::Status::MagicNumber) {
            throw Toastbox::RuntimeError("invalid magic number (expected:0x%08jx got:0x%08jx)",
                (uintmax_t)STM::Status::MagicNumber, (uintmax_t)status.magic);
        }
        
        return status;
    }
    
    STM::BatteryStatus batteryStatusGet() {
        const STM::Cmd cmd = { .op = STM::Op::BatteryStatusGet };
        _sendCmd(cmd);
        
        STM::BatteryStatus status = {};
        _dev.read(STM::Endpoint::DataIn, status);
        return status;
    }
    
    void bootloaderInvoke() {
        const STM::Cmd cmd = { .op = STM::Op::BootloaderInvoke };
        _sendCmd(cmd);
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
    }
    
    // MARK: - STMLoader Commands
    void stmWrite(uintptr_t addr, const void* data, size_t len) {
        assert(_mode == STM::Status::Mode::STMLoader);
        
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
        _dev.write(STM::Endpoint::DataOut, data, len);
    }
    
    void stmReset(uintptr_t entryPointAddr) {
        assert(_mode == STM::Status::Mode::STMLoader);
        
        if (entryPointAddr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)entryPointAddr);
        
        const STM::Cmd cmd = {
            .op = STM::Op::STMReset,
            .arg = { .STMReset = { .entryPointAddr = (uint32_t)entryPointAddr } }
        };
        _sendCmd(cmd);
    }
    
    // MARK: - STMApp Commands
    void iceRAMWrite(const void* data, size_t len) {
        assert(_mode == STM::Status::Mode::STMApp);
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::ICERAMWrite,
            .arg = { .ICERAMWrite = { .len = (uint32_t)len } },
        };
        _sendCmd(cmd);
        // Send data
        _dev.write(STM::Endpoint::DataOut, data, len);
        _checkStatus("ICERAMWrite command failed");
    }
    
    void iceFlashRead(uintptr_t addr, void* data, size_t len) {
        assert(_mode == STM::Status::Mode::STMApp);
        
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
        _dev.read(STM::Endpoint::DataIn, data, len);
        _checkStatus("ICEFlashRead command failed");
    }
    
    void iceFlashWrite(uintptr_t addr, const void* data, size_t len) {
        assert(_mode == STM::Status::Mode::STMApp);
        
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
        _dev.write(STM::Endpoint::DataOut, data, len);
        _checkStatus("ICEFlashWrite command failed");
    }
    
    void mspHostModeSet(bool en) {
        assert(_mode == STM::Status::Mode::STMApp);
        const STM::Cmd cmd = {
            .op = STM::Op::MSPHostModeSet,
            .arg = { .MSPHostModeSet = { .en = en } },
        };
        _sendCmd(cmd);
        _checkStatus("MSPHostModeSet command failed");
    }
    
//    MSP::State::Header mspStateHeaderRead() {
//        assert(_mode == STM::Status::Mode::STMApp);
//        const STM::Cmd cmd = {
//            .op = STM::Op::MSPStateRead,
//            .arg = { .MSPStateRead = { .len = sizeof(MSP::State::Header) } },
//        };
//        _sendCmd(cmd);
//        _checkStatus("MSPStateRead command failed");
//        
//        MSP::State state;
//        _dev.read(STM::Endpoint::DataIn, state);
//        return state;
//    }
    
//    template <typename T>
//    void mspStateRead(T& t) {
//        assert(_mode == STM::Status::Mode::STMApp);
//        const STM::Cmd cmd = {
//            .op = STM::Op::MSPStateRead,
//            .arg = { .MSPStateRead = { .len = sizeof(t) } },
//        };
//        _sendCmd(cmd);
//        _checkStatus("MSPStateRead command failed");
//        
//        _dev.read(STM::Endpoint::DataIn, t);
//    }
    
    MSP::State mspStateRead() {
        assert(_mode == STM::Status::Mode::STMApp);
        
        // Read MSP::State::Header and make sure we understand it
        {
            const STM::Cmd cmd = {
                .op = STM::Op::MSPStateRead,
                .arg = { .MSPStateRead = { .len = sizeof(MSP::State::Header) } },
            };
            _sendCmd(cmd);
            _checkStatus("MSPStateRead command failed (header)");
            
            MSP::State::Header header;
            _dev.read(STM::Endpoint::DataIn, header);
            
            if (header.magic != MSP::StateHeader.magic) {
                throw Toastbox::RuntimeError("invalid MSP::State magic number (expected: 0x%08jx, got: 0x%08jx)",
                    (uintmax_t)MSP::StateHeader.magic,
                    (uintmax_t)header.magic
                );
            }
            
            if (header.version != MSP::StateHeader.version) {
                throw Toastbox::RuntimeError("unrecognized MSP::State version (expected: 0x%02jx, got: 0x%02jx)",
                    (uintmax_t)MSP::StateHeader.version,
                    (uintmax_t)header.version
                );
            }
        }
        
        // Header looks good; read the full MSP::State
        {
            const STM::Cmd cmd = {
                .op = STM::Op::MSPStateRead,
                .arg = { .MSPStateRead = { .len = sizeof(MSP::State) } },
            };
            _sendCmd(cmd);
            _checkStatus("MSPStateRead command failed (header+payload)");
            
            MSP::State state;
            _dev.read(STM::Endpoint::DataIn, state);
            
            return state;
        }
    }
    
    void mspStateWrite(const MSP::State& state) {
        assert(_mode == STM::Status::Mode::STMApp);
        
        const STM::Cmd cmd = {
            .op = STM::Op::MSPStateWrite,
            .arg = { .MSPStateWrite = { .len = sizeof(state) } },
        };
        // Send command
        _sendCmd(cmd);
        // Send data
        _dev.write(STM::Endpoint::DataOut, &state, sizeof(state));
        // Check status
        _checkStatus("MSPStateWrite command failed");
    }
    
    Time::Instant mspTimeGet() {
        assert(_mode == STM::Status::Mode::STMApp);
        const STM::Cmd cmd = { .op = STM::Op::MSPTimeGet };
        _sendCmd(cmd);
        _checkStatus("MSPTimeGet command failed");
        
        Time::Instant time;
        _dev.read(STM::Endpoint::DataIn, time);
        return time;
    }
    
    void mspTimeSet(Time::Instant time) {
        assert(_mode == STM::Status::Mode::STMApp);
        const STM::Cmd cmd = {
            .op = STM::Op::MSPTimeSet,
            .arg = { .MSPTimeSet = { .time = time } },
        };
        _sendCmd(cmd);
        _checkStatus("MSPTimeSet command failed");
    }
    
    void mspSBWConnect() {
        assert(_mode == STM::Status::Mode::STMApp);
        const STM::Cmd cmd = { .op = STM::Op::MSPSBWConnect };
        _sendCmd(cmd);
        _checkStatus("MSPSBWConnect command failed");
    }
    
    void mspSBWDisconnect() {
        assert(_mode == STM::Status::Mode::STMApp);
        const STM::Cmd cmd = { .op = STM::Op::MSPSBWDisconnect };
        _sendCmd(cmd);
        _checkStatus("MSPSBWDisconnect command failed");
    }
    
    void mspSBWRead(uintptr_t addr, void* data, size_t len) {
        assert(_mode == STM::Status::Mode::STMApp);
        
        if (addr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)addr);
        
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::MSPSBWRead,
            .arg = {
                .MSPSBWRead = {
                    .addr = (uint32_t)addr,
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Read data
        _dev.read(STM::Endpoint::DataIn, data, len);
        _checkStatus("MSPSBWRead command failed");
    }
    
    void mspSBWWrite(uintptr_t addr, const void* data, size_t len) {
        assert(_mode == STM::Status::Mode::STMApp);
        
        if (addr >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)addr);
        
        if (len >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)len);
        
        const STM::Cmd cmd = {
            .op = STM::Op::MSPSBWWrite,
            .arg = {
                .MSPSBWWrite = {
                    .addr = (uint32_t)addr,
                    .len = (uint32_t)len,
                },
            },
        };
        _sendCmd(cmd);
        // Send data
        _dev.write(STM::Endpoint::DataOut, data, len);
        _checkStatus("MSPSBWWrite command failed");
    }
    
    void mspSBWDebug(const STM::MSPSBWDebugCmd* cmds, size_t cmdsLen, void* resp, size_t respLen) {
        assert(_mode == STM::Status::Mode::STMApp);
        
        if (cmdsLen >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)cmdsLen);
        
        if (respLen >= std::numeric_limits<uint32_t>::max())
            throw Toastbox::RuntimeError("%jx doesn't fit in uint32_t", (uintmax_t)respLen);
        
        const STM::Cmd cmd = {
            .op = STM::Op::MSPSBWDebug,
            .arg = {
                .MSPSBWDebug = {
                    .cmdsLen = (uint32_t)cmdsLen,
                    .respLen = (uint32_t)respLen,
                },
            },
        };
        _sendCmd(cmd);
        
        // Write the MSPDebugCmds
        if (cmdsLen) {
            _dev.write(STM::Endpoint::DataOut, cmds, cmdsLen*sizeof(STM::MSPSBWDebugCmd));
        }
        
        // Read back the queued data
        if (respLen) {
            _dev.read(STM::Endpoint::DataIn, resp, respLen);
        }
        
        _checkStatus("MSPDebug command failed");
    }
    
    STM::SDCardInfo sdInit() {
        assert(_mode == STM::Status::Mode::STMApp);
        
        const STM::Cmd cmd = { .op = STM::Op::SDInit };
        _sendCmd(cmd);
        _checkStatus("SDInit command failed");
        
        STM::SDCardInfo cardInfo = {};
        _dev.read(STM::Endpoint::DataIn, cardInfo);
        return cardInfo;
    }
    
    void sdRead(SD::Block block) {
        assert(_mode == STM::Status::Mode::STMApp);
        
        const STM::Cmd cmd = {
            .op = STM::Op::SDRead,
            .arg = {
                .SDRead = {
                    .block = block,
                },
            },
        };
        _sendCmd(cmd);
        _checkStatus("SDRead command failed");
    }
    
    void imgInit() {
        assert(_mode == STM::Status::Mode::STMApp);
        
        const STM::Cmd cmd = { .op = STM::Op::ImgInit, };
        _sendCmd(cmd);
        _checkStatus("ImgInit command failed");
    }
    
    struct ImgExposure {
        uint16_t coarseIntTime  = 0;
        uint16_t fineIntTime    = 0;
        uint16_t analogGain     = 0;
    };
    
    void imgExposureSet(const ImgExposure& exp) {
        assert(_mode == STM::Status::Mode::STMApp);
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
    
    STM::ImgCaptureStats imgCapture(uint8_t dstRAMBlock, uint8_t skipCount, Img::Size imgSize) {
        assert(_mode == STM::Status::Mode::STMApp);
        
        const STM::Cmd cmd = {
            .op = STM::Op::ImgCapture,
            .arg = {
                .ImgCapture = {
                    .dstRAMBlock = 0,
                    .skipCount = skipCount,
                    .size = imgSize,
                },
            },
        };
        
        _sendCmd(cmd);
        
        STM::ImgCaptureStats stats;
        _dev.read(STM::Endpoint::DataIn, stats);
        _checkStatus("ImgCapture command failed");
        return stats;
    }
    
    std::unique_ptr<uint8_t[]> imgReadout(Img::Size size) {
        assert(_mode == STM::Status::Mode::STMApp);
        const size_t imageLen = (size==Img::Size::Full ? ImgSD::Full::ImagePaddedLen : ImgSD::Thumb::ImagePaddedLen);
        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(imageLen);
        const size_t lenGot = _dev.read(STM::Endpoint::DataIn, buf.get(), imageLen);
        if (lenGot != imageLen) {
            throw Toastbox::RuntimeError("expected 0x%jx bytes, got 0x%jx bytes", (uintmax_t)imageLen, (uintmax_t)lenGot);
        }
        
        // Validate checksum
        const size_t checksumOffset = (size==Img::Size::Full ? Img::Full::ChecksumOffset : Img::Thumb::ChecksumOffset);
        const uint32_t checksumExpected = ChecksumFletcher32(buf.get(), checksumOffset);
        uint32_t checksumGot = 0;
        memcpy(&checksumGot, (uint8_t*)buf.get()+checksumOffset, Img::ChecksumLen);
        if (checksumGot != checksumExpected) {
            throw Toastbox::RuntimeError("invalid checksum (expected:0x%08x got:0x%08x)", checksumExpected, checksumGot);
        }
        
        return buf;
    }
    
    void readout(void* dst, size_t len) {
        assert(_mode == STM::Status::Mode::STMApp);
        if (!len) return; // Short-circuit if there's no data to read
        
        const size_t mps = _dev.maxPacketSize(STM::Endpoint::DataIn);
        if (len % mps) {
            throw Toastbox::RuntimeError("len isn't a multiple of max packet size (len: %ju, max packet size: %ju)", (uintmax_t)len, (uintmax_t)mps);
        }
        
        _dev.read(STM::Endpoint::DataIn, dst, len);
        
//        std::unique_ptr<uint8_t[]> buf = std::make_unique<uint8_t[]>(Img::PaddedLen);
//        const size_t lenGot = _dev.read(STM::Endpoint::DataIn, buf.get(), Img::PaddedLen);
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
    void _endpointReset(uint8_t ep) {
        namespace USB = Toastbox::USB;
        if ((ep&USB::Endpoint::DirectionMask) == USB::Endpoint::DirectionOut) {
            // Send 2x ZLPs + sentinel
            _dev.write(ep, nullptr, 0);
            _dev.write(ep, nullptr, 0);
            const uint8_t sentinel = 0;
            _dev.write(ep, &sentinel, sizeof(sentinel));
        
        } else {
            constexpr size_t BufSize = 16*1024;
            auto buf = std::make_unique<uint8_t[]>(BufSize);
            
            // Flush data from the endpoint until we get a ZLP
            for (;;) {
                const size_t len = _dev.read(ep, buf.get(), BufSize);
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
        // The device will reject a control request if the previous request is still in progress.
        constexpr int TryCount = 2;
        for (int i=0; i<TryCount; i++) {
            try {
                _dev.vendorRequestOut(0, cmd);
                break;
                
            } catch (...) {
                // We failed, so if this is the last attempt, throw the exception
                if (i == TryCount-1) throw;
            }
        }
        _checkStatus("command rejected");
    }
    
    void _checkStatus(const char* errMsg) {
        // Wait for completion and throw on failure
        bool s = false;
        _dev.read(STM::Endpoint::DataIn, s);
        if (!s) throw std::runtime_error(errMsg);
    }
    
    USBDevice _dev;
    std::string _serial = {};
    STM::Status::Mode _mode = STM::Status::Mode::None;
};
