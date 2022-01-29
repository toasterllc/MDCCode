#pragma once
#include "Img.h"

namespace MSP {
    
    using Sec = uint32_t;
    
    struct [[gnu::packed]] Time {
        Sec start = 0;
        Sec delta = 0;
    };
    
    // ImgRingBuf: stats to track captured images
    struct [[gnu::packed]] ImgRingBuf {
        static constexpr uint32_t MagicNumber = 0xCAFEBABE;
        uint32_t magic = 0;
        struct [[gnu::packed]] {
            Img::Id idBegin     = 0;
            Img::Id idEnd       = 0;
            uint16_t widx       = 0;
            uint16_t ridx       = 0;
            uint16_t full       = false; // uint16_t (instead of bool) for alignment
        } buf;
        
        template <typename T> // Templated so that FindLatest() works with or without const/volatile
        static bool FindLatest(T*& newest, T*& oldest) {
            T* ringBuf = newest;
            T* ringBuf2 = oldest;
            
            if (ringBuf->magic==ImgRingBuf::MagicNumber && ringBuf2->magic==ImgRingBuf::MagicNumber) {
                if (ringBuf->buf.idEnd >= ringBuf2->buf.idEnd) {
                    newest = ringBuf;
                    oldest = ringBuf2;
                    return true;
                    
                } else {
                    newest = ringBuf2;
                    oldest = ringBuf;
                    return true;
                }
            
            } else if (ringBuf->magic == ImgRingBuf::MagicNumber) {
                newest = ringBuf;
                oldest = ringBuf2;
                return true;
            
            } else if (ringBuf2->magic == ImgRingBuf::MagicNumber) {
                newest = ringBuf2;
                oldest = ringBuf;
                return true;
            
            } else {
                return false;
            }
        }
    };
    
    struct [[gnu::packed]] AbortEvent {
        Time time       = {};
        uint16_t domain = 0;
        uint16_t line   = 0;
    };
    
    static constexpr uint32_t StateAddr = 0x1800;
    
    struct [[gnu::packed]] State {
        static constexpr uint32_t MagicNumber   = 0xDECAFBAD;
        static constexpr uint32_t Version       = 0;
        static constexpr uint32_t MagicVersion  = MagicNumber+Version;
        
        const uint32_t magicVersion = MagicVersion;
        
        // startTime: the time set by the outside world (seconds since reference date)
        struct [[gnu::packed]] {
            Sec time        = 0;
            uint16_t valid  = false; // uint16_t (instead of bool) for alignment
        } startTime = {};
        
        struct [[gnu::packed]] {
            // cap: image capacity
            uint32_t cap        = 0;
            // ringBuf: tracks captured images
            ImgRingBuf ringBuf  = {};
            // ringBuf2: copy of `ringBuf` in case there's a power failure
            ImgRingBuf ringBuf2 = {};
        } img = {};
        
        // abort: records aborts that have occurred
        struct [[gnu::packed]] {
            uint16_t eventsCount    = 0;
            AbortEvent events[3]    = {};
        } abort = {};
    };

} // namespace MSP
