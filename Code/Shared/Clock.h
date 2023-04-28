#pragma once
#include <ratio>
#include "chrono.h" // Local version of <chrono> header

struct Clock {
    // TicksFreq / TicksPeriod: frequency / period of device's ticks timebase
    using TicksFreq   = std::ratio<16>;
    using TicksPeriod = std::ratio_divide<std::ratio<1>,TicksFreq>;
    
    // Ticks: a duration in ticks
    using Ticks = std::chrono::duration<uint64_t, TicksPeriod>;
    using Ticks32 = std::chrono::duration<uint32_t, TicksPeriod>;
    using Ticks16 = std::chrono::duration<uint16_t, TicksPeriod>;
    
    using Instant = std::chrono::time_point<Clock, duration>;
    
    static constexpr Instant AbsoluteBit = (Instant)1<<63;
    
    // Absolute(): returns whether the time instant is an absolute time (versus a relative time)
    // The difference between the two is that an absolute time is a time delta since the epoch
    // (AbsoluteEpochUnix), whereas a relative time is a time delta since the device booting. A
    // relative time therefore can't be converted to an absolute time without knowing the
    // absolute time that the device booted.
    static constexpr bool Absolute(const Instant& t) {
        return t&AbsoluteBit;
    }
    
    using rep = Time::Ticks::rep;
    using period = Time::TicksPeriod;
    using duration = std::chrono::duration<rep, period>;
    using time_point = Instant;
    static const bool is_steady = true;
};
