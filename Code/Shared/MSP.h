#pragma once
#include <optional>
#include <atomic>
#include "Img.h"
#include "SD.h"

namespace MSP {
    
    using Time = uint64_t;
    
    using BatterySample = uint16_t;
    static constexpr BatterySample BatterySampleMin = 0;
    static constexpr BatterySample BatterySampleMax = 1000;    
    
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
        
        static void Set(ImgRingBuf& a, const ImgRingBuf& b) {
            a.valid = false;
            // Ensure that `valid` is reset before we modify `buf`
            std::atomic_signal_fence(std::memory_order_seq_cst);
            a.buf = b.buf;
            // Ensure that `buf` is valid before we set `valid`
            std::atomic_signal_fence(std::memory_order_seq_cst);
            a.valid = true;
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
    
    // AbortType: a (domain,line) tuple that uniquely identifies a type of abort
    struct [[gnu::packed]] AbortType {
        uint16_t domain = 0;
        uint16_t line   = 0;
    };
    static_assert(!(sizeof(AbortType) % 2)); // Check alignment
    
    // AbortHistory: records history of an abort type, where an abort type is a (domain,line) tuple
    struct [[gnu::packed]] AbortHistory {
        AbortType type          = {};
        Time timestampEarliest  = {};
        Time timestampLatest    = {};
        uint16_t count          = 0;
    };
    static_assert(!(sizeof(AbortHistory) % 2)); // Check alignment
    
    static constexpr uint32_t StateAddr = 0x1800;
    
    struct [[gnu::packed]] State {
        struct [[gnu::packed]] Header {
            uint32_t magic   = 0;
            uint16_t version = 0;
            uint16_t length  = 0;
        };
        
        Header header = {};
        
        struct [[gnu::packed]] {
            // cardId: the SD card's CID, used to determine when the SD card has been
            // changed, and therefore we need to update `imgCap` and reset `ringBufs`
            SD::CardId cardId;
            // imgCap: image capacity; the number of images that bounds the ring buffer
            uint32_t imgCap = 0;
            // thumbBlockStart: the first block of the thumbnail image region.
            // The SD card is broken into 2 regions (fullSize, thumbnails), to allow
            // the thumbnails to be efficiently read from the host. `thumbBlockStart`
            // is the start of the thumbnail region.
            SD::Block thumbBlockStart = 0;
            // ringBufs: tracks captured images on the SD card; 2 copies in case there's a
            // power failure while updating one
            ImgRingBuf imgRingBufs[2] = {};
            bool valid = false;
            uint8_t _pad = 0;
        } sd = {};
        static_assert(!(sizeof(sd) % 2)); // Check alignment
        
        // aborts: records aborts that have occurred
        AbortHistory aborts[5] = {};
        static_assert(!(sizeof(aborts) % 2)); // Check alignment
    };
    
    static constexpr State::Header StateHeader = {
        .magic   = 0xDECAFBAD,
        .version = 0,
        .length  = sizeof(State)-sizeof(State::Header),
    };
    
    static constexpr uint8_t I2CAddr = 0x55;
    
    struct [[gnu::packed]] Cmd {
        enum class Op : uint8_t {
            None,
            StateRead,
            StateWrite,
            LEDSet,
            TimeSet,
            HostModeSet,
            VDDIMGSDSet,
            BatterySample,
        };
        
        Op op = Op::None;
        union {
            struct [[gnu::packed]] {
                uint8_t chunk;
            } StateRead;
            
            struct [[gnu::packed]] {
                uint8_t chunk;
                uint8_t data[8];
            } StateWrite;
            
            struct [[gnu::packed]] {
                uint8_t red;
                uint8_t green;
            } LEDSet;
            
            struct [[gnu::packed]] {
                Time time;
            } TimeSet;
            
            struct [[gnu::packed]] {
                uint8_t en;
            } HostModeSet;
            
            struct [[gnu::packed]] {
                uint8_t en;
            } VDDIMGSDSet;
        } arg;
    };
    
    struct [[gnu::packed]] Resp {
        uint8_t ok = false;
        union {
            struct [[gnu::packed]] {
                uint8_t data[8];
            } StateRead;
            
            struct [[gnu::packed]] {
                uint16_t sample;
            } BatterySample;
        } arg;
    };

} // namespace MSP
