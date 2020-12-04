#pragma once
#include <chrono>

// TODO: choose a name for this
namespace MyTime {
    using Instant = std::chrono::steady_clock::time_point;
    
    inline Instant Now() {
        return std::chrono::steady_clock::now();
    }
    
    inline uint64_t DurationNs(Instant start, Instant end=Now()) {
        return std::chrono::duration_cast<std::chrono::nanoseconds>(end-start).count();
    }
    
    inline uint64_t DurationMs(Instant start, Instant end=Now()) {
        return std::chrono::duration_cast<std::chrono::milliseconds>(end-start).count();
    }
}
