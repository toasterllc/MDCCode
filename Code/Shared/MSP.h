#pragma once

namespace MSP {
    
    using Sec = uint32_t;
    
    struct [[gnu::packed]] Time {
        Sec start = 0;
        Sec delta = 0;
    };
    
    // img: stats to track captured images
    struct [[gnu::packed]] ImgRingBuf {
        static constexpr uint32_t MagicNumber = 0xCAFEBABE;
        uint32_t magic = 0;
        struct [[gnu::packed]] {
            uint32_t id     = 0;
            uint16_t widx   = 0;
            uint16_t ridx   = 0;
            uint16_t full   = false; // uint16_t (instead of bool) for alignment
        } buf;
    };
    
    struct [[gnu::packed]] AbortEvent {
        Time time       = {};
        uint16_t domain = 0;
        uint16_t line   = 0;
    };
    
    struct [[gnu::packed]] State {
        static constexpr uint16_t Version = 0x4242;
        const uint16_t version = Version;
        
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
