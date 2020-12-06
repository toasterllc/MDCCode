#pragma once
#include <chrono>

namespace MyTime {
    using Instant = std::chrono::steady_clock::time_point;
    
    inline Instant Now() {
        return std::chrono::steady_clock::now();
    }
    
    inline uint64_t DurationNs(Instant t1, Instant t2=Now()) {
        return std::chrono::duration_cast<std::chrono::nanoseconds>(t2-t1).count();
    }
    
    inline uint64_t DurationMs(Instant t1, Instant t2=Now()) {
        return std::chrono::duration_cast<std::chrono::milliseconds>(t2-t1).count();
    }
}
