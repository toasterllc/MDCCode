#pragma once
#include <optional>
#include "Img.h"
#include "SD.h"

namespace MSP {
    
    using Sec = uint32_t;
    
    struct [[gnu::packed]] Time {
        Sec start = 0;
        Sec delta = 0;
    };
    
    // ImgRingBuf: stats to track captured images
    struct [[gnu::packed]] ImgRingBuf {
        struct [[gnu::packed]] {
            Img::Id idBegin     = 0;
            Img::Id idEnd       = 0;
            uint16_t widx       = 0;
            uint16_t ridx       = 0;
            bool full           = false;
        } buf;
        volatile bool valid = false;
        
//        ImgRingBuf& operator=(const ImgRingBuf& x) {
//            valid = false;
//            buf = x.buf;
//            valid = true;
//            return *this;
//        }
//        
//        template <typename T>
//        static void _ImgRingBufSet(volatile MSP::ImgRingBuf& dst, const T& src) {
//            FRAMWriteEn writeEn; // Enable FRAM writing
//            
//            dst.valid = false;
//            atomic_thread_fence(std::memory_order_seq_cst);
//            
//            (const_cast<MSP::ImgRingBuf&>(dst)).buf = const_cast<MSP::ImgRingBuf&>(src).buf;
//            atomic_thread_fence(std::memory_order_seq_cst);
//            
//            dst.valid = true;
//        }
        
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
        
//        static bool FindLatest(const ImgRingBuf*& newest, const ImgRingBuf*& oldest) {
//            const ImgRingBuf*const ringBuf = newest;
//            const ImgRingBuf*const ringBuf2 = oldest;
//            
//            if (ringBuf->valid && ringBuf2->valid) {
//                if (ringBuf->buf.idEnd >= ringBuf2->buf.idEnd) {
//                    newest = ringBuf;
//                    oldest = ringBuf2;
//                    return true;
//                    
//                } else {
//                    newest = ringBuf2;
//                    oldest = ringBuf;
//                    return true;
//                }
//            
//            } else if (ringBuf->valid) {
//                newest = ringBuf;
//                oldest = ringBuf2;
//                return true;
//            
//            } else if (ringBuf2->valid) {
//                newest = ringBuf2;
//                oldest = ringBuf;
//                return true;
//            
//            } else {
//                return false;
//            }
//        }
    };
    
    struct [[gnu::packed]] AbortEvent {
        Time time       = {};
        uint16_t domain = 0;
        uint16_t line   = 0;
    };
    
    static constexpr uint32_t StateAddr = 0x1800;
    
    struct [[gnu::packed]] State {
        static constexpr uint32_t MagicNumber   = 0xDECAFBAD;
        static constexpr uint16_t Version       = 0;
        
        const uint32_t magic = MagicNumber;
        const uint16_t version = Version;
        
        // startTime: the time set by the outside world (seconds since reference date)
        struct [[gnu::packed]] {
            Sec time        = 0;
            volatile bool valid = false;
            uint8_t _pad = 0;
        } startTime = {};
        
        struct [[gnu::packed]] {
            // cardId: the SD card's CID, used to determine when the SD card has been
            // changed, and therefore we need to update `imgCap` and reset `ringBufs`
            SD::CardId cardId;
            // imgCap: image capacity; the number of images that bounds the ring buffer
            uint32_t imgCap = 0;
            // ringBufs: tracks captured images on the SD card; 2 copies in case there's a
            // power failure
            ImgRingBuf imgRingBufs[2] = {};
            volatile bool valid = false;
            uint8_t _pad = 0;
        } sd = {};
        
        // abort: records aborts that have occurred
        struct [[gnu::packed]] {
            AbortEvent events[3]            = {};
            volatile uint16_t eventsCount   = 0;
        } abort = {};
    };

} // namespace MSP
