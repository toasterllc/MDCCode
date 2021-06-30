#pragma once
#include <IOKit/IOKitLib.h>
#include "USBInterface.h"
#include "RuntimeError.h"

class USBPipe {
public:
    using Milliseconds = uint32_t;
    
    Enum(uint32_t, Option, Options,
        None                    = 0,
        WriteZeroLengthPacket   = 1<<0, // See _writeZLPIfNeeded() comment for more info
    );
    
    // Default constructor: empty
    USBPipe() {}
    
    USBPipe(USBInterface& interface, uint8_t idx, Option opts=Options::None)
    : _interface(interface), _idx(idx), _opts(opts) {
        IOUSBEndpointProperties props = {
            .bVersion = kUSBEndpointPropertiesVersion3,
        };
        IOReturn ior = (*_interface.interface())->GetPipePropertiesV3(_interface.interface(), _idx, &props);
        if (ior != kIOReturnSuccess) throw RuntimeError("GetPipePropertiesV3() failed: 0x%x", ior);
        _maxPacketSize = props.wMaxPacketSize;
        if (!_maxPacketSize) throw RuntimeError("_maxPacketSize == 0");
    }
    
    operator bool() const { return _interface; }
    
    template <typename T>
    void write(T& x, Milliseconds timeout=0) const {
        IOReturn ior = (*_interface.interface())->WritePipeTO(_interface.interface(), _idx, (void*)&x, sizeof(x), 0, timeout);
        if (ior != kIOReturnSuccess) throw RuntimeError("WritePipeTO() failed: 0x%x", ior);
        _writeZLPIfNeeded(sizeof(x), timeout);
    }
    
    void writeBuf(const void* buf, size_t len, Milliseconds timeout=0) const {
        IOReturn ior = (*_interface.interface())->WritePipeTO(_interface.interface(), _idx, (void*)buf, (uint32_t)len, 0, timeout);
        if (ior != kIOReturnSuccess) throw RuntimeError("WritePipeTO() failed: 0x%x", ior);
        _writeZLPIfNeeded(len, timeout);
    }
    
    template <typename T>
    void read(T& t, Milliseconds timeout=0) const {
        uint32_t len32 = (uint32_t)sizeof(t);
        IOReturn ior = (*_interface.interface())->ReadPipeTO(_interface.interface(), _idx, &t, &len32, 0, timeout);
        if (ior != kIOReturnSuccess) throw RuntimeError("ReadPipe() failed: 0x%x", ior);
        if (len32 != sizeof(t)) throw RuntimeError("ReadPipe() returned bad length (expected %ju bytes, got %ju bytes)",
            (uintmax_t)sizeof(t), (uintmax_t)len32);
    }
    
    void readBuf(void* buf, size_t len, Milliseconds timeout=0) const {
        uint32_t len32 = (uint32_t)len;
        IOReturn ior = (*_interface.interface())->ReadPipeTO(_interface.interface(), _idx, buf, &len32, 0, timeout);
        if (ior != kIOReturnSuccess) throw RuntimeError("ReadPipe() failed: 0x%x", ior);
        if (len32 != len) throw RuntimeError("ReadPipe() returned bad length (expected %ju bytes, got %ju bytes)",
            (uintmax_t)len, (uintmax_t)len32);
    }
    
    void reset() const {
        IOReturn ior = (*_interface.interface())->ResetPipe(_interface.interface(), _idx);
        if (ior != kIOReturnSuccess) throw RuntimeError("ResetPipe() failed: 0x%x", ior);
    }
    
private:
    USBInterface _interface;
    uint8_t _idx = 0;
    Option _opts = Options::None;
    uint16_t _maxPacketSize = 0;
    
    // Sometimes we need to manually send a zero-length packet (ZLP) to terminate a transfer.
    // This is needed because transfers are terminated when either:
    // 
    //   1. the expected number of bytes has been received, or
    //   2. a packet length is less than the max packet size, or
    //   3. a zero-length packet is received.
    //
    // In some cases #1 and #2 don't apply, and therefore #3 must be employed manually.
    // (For example: our STM32 bootloader requests the number of bytes that will fill a
    // certain RAM region, but allows any number of bytes up to that limit to be received,
    // so the STM32 bootloader doesn't know the number of bytes to be received. Hence #1
    // doesn't apply. #2 also doesn't apply when the data being sent is a multiple of the
    // max packet size. Therefore a ZLP must be sent.)
    // 
    // Originally we thought that the USB APIs would automatically send a ZLP if the
    // transfer size is a multiple of the max packet size, and therefore we didn't have to
    // send ZLPs ourself. Empirically that doesn't seem to be the case -- the USB APIs do not
    // send ZLPs automatically. In hindsight that makes sense, because the USB APIs cannot
    // know whether #1 (above) applies, and if it did, the USB APIs would send a ZLP when it
    // wasn't needed or expected. So it makes sense that we have to send ZLPs manually.
    void _writeZLPIfNeeded(size_t s, Milliseconds timeout) const {
        // Bail if we're not supposed to send zero-length packets (ZLP)
        if (!(_opts & Options::WriteZeroLengthPacket)) return;
        // Bail if the length of the original data was already 0
        if (!s) return;
        // Bail if the length of the original data wasn't a multiple of the max packet size,
        // in which case the short packet already implicitly indicated the end of the data,
        // so there's no need for a ZLP.
        if (s % _maxPacketSize) return;
        
        IOReturn ior = (*_interface.interface())->WritePipeTO(_interface.interface(), _idx, nullptr, 0, 0, timeout);
        if (ior != kIOReturnSuccess) throw RuntimeError("WritePipeTO() failed: 0x%x", ior);
    }
};
