#pragma once
#include <chrono>

class TimeInstant {
public:
    TimeInstant() : _t(std::chrono::steady_clock::now()) {}
    
    uint64_t durationNs() const {
        return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-_t).count();
    }
    
    uint64_t durationMs() const {
        return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-_t).count();
    }
    
private:
    std::chrono::steady_clock::time_point _t;
};
