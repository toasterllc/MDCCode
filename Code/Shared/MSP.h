#pragma once
#include <optional>
#include "Img.h"
#include "SD.h"

namespace MSP {
    
    using Time = uint64_t;
    
    static constexpr bool TimeIsAbsolute(const Time& t) {
        return t&((uint64_t)1<<63);
    }
    
    static constexpr Time TimeAbsoluteUnixReference = 1640995200; // 2022-01-01 00:00:00 +0000
    static constexpr Time TimeAbsoluteBase = (Time)1<<63;
    
    static constexpr uint64_t UnixTimeFromTime(Time t) {
        return (t&(~TimeAbsoluteBase)) + TimeAbsoluteUnixReference;
    }
    
    static constexpr uint64_t TimeFromUnixTime(uint64_t t) {
        return TimeAbsoluteBase | (t-TimeAbsoluteUnixReference);
    }
    
    // ImgRingBuf: stats to track captured images
    struct [[gnu::packed]] ImgRingBuf {
        struct [[gnu::packed]] {
            Img::Id idBegin = 0;
            Img::Id idEnd   = 0;
            uint32_t widx   = 0;
            uint32_t ridx   = 0;
            bool full       = false;
        } buf;
        bool valid = false;
        
        ImgRingBuf& operator=(const ImgRingBuf& x) {
            valid = false;
            
            // Ensure that `valid` is reset before we modify `buf`
            std::atomic_signal_fence(std::memory_order_seq_cst);
            buf = x.buf;
            // Ensure that `buf` is valid before we set `valid`
            std::atomic_signal_fence(std::memory_order_seq_cst);
            
            valid = true;
            return *this;
        }
        
        static std::optional<int> Compare(const ImgRingBuf& a, const ImgRingBuf& b) {
            if (a.valid && b.valid) {
                if (a.buf.idEnd > b.buf.idEnd) return 1;
                else if (a.buf.idEnd < b.buf.idEnd) return -1;
                else return 0;
            
            } else if (a.valid) {
                return 1;
            
            } else if (b.valid) {
                return -1;
            }
            return std::nullopt;
        }

    };
    
    struct [[gnu::packed]] AbortEvent {
        Time timestamp  = {};
        uint16_t domain = 0;
        uint16_t line   = 0;
    };
    
    static constexpr uint32_t StateAddr = 0x1800;
    
    struct [[gnu::packed]] State {
        static constexpr uint32_t MagicNumber   = 0xDECAFBAD;
        static constexpr uint16_t Version       = 0;
        
        const uint32_t magic = MagicNumber;
        const uint16_t version = Version;
        
        // startTime: the absolute time set by the outside world (seconds since reference date)
        struct [[gnu::packed]] {
            Time time = 0;
            bool valid = false;
            uint8_t _pad = 0;
        } startTime = {};
        static_assert(!(sizeof(startTime) % 2)); // Check alignment
        
        struct [[gnu::packed]] {
            // cardId: the SD card's CID, used to determine when the SD card has been
            // changed, and therefore we need to update `imgCap` and reset `ringBufs`
            SD::CardId cardId;
            // imgCap: image capacity; the number of images that bounds the ring buffer
            uint32_t imgCap = 0;
            // fullSizeBlockStart: the first block of the full-size image region.
            // The SD card is broken into 2 regions (thumbnails, fullSize), to allow
            // the thumbnails to be efficiently read from the host. `fullSizeBlockStart`
            // is the start of the full-size region.
            SD::Block fullSizeBlockStart = 0;
            // ringBufs: tracks captured images on the SD card; 2 copies in case there's a
            // power failure while updating one
            ImgRingBuf imgRingBufs[2] = {};
            bool valid = false;
            uint8_t _pad = 0;
        } sd = {};
        static_assert(!(sizeof(sd) % 2)); // Check alignment
        
        // abort: records aborts that have occurred
        struct [[gnu::packed]] {
            AbortEvent events[3] = {};
            uint16_t eventsCount = 0;
        } abort = {};
        static_assert(!(sizeof(abort) % 2)); // Check alignment
    };

} // namespace MSP
