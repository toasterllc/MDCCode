#pragma once

namespace MSP {
    
    using Sec = uint32_t;
    
    struct [[gnu::packed]] State {
        static constexpr uint16_t Version = 0x4242;
        
        const uint16_t version = Version;
        
        // startTime: the time set by the outside world (seconds since reference date)
        struct [[gnu::packed]] {
            Sec time        = 0;
            uint16_t valid  = false; // uint16_t (instead of bool) for alignment
        } startTime;
        
        // img: stats to track captured images
        struct [[gnu::packed]] {
            uint32_t counter    = 0;
            uint16_t write      = 0;
            uint16_t read       = 0;
            uint16_t full       = false; // uint16_t (instead of bool) for alignment
        } img;
        
        // abort: records aborts that have occurred
        struct [[gnu::packed]] {
            uint16_t count = 0;
            
            struct [[gnu::packed]] {
                Sec time        = 0;
                uint16_t domain = 0;
                uint16_t line   = 0;
            } events[3] = {};
        } abort;
    };

} // namespace MSP
