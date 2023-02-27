#pragma once
#include <chrono>
#include <cassert>
#include "date/date.h"
#include "date/tz.h"

namespace Time {

// Epoch: 2022-01-01 00:00:00 +0000
static constexpr std::chrono::time_point<date::utc_clock> Epoch(std::chrono::seconds(1640995227));

// Current(): returns the current time instant
//
// Note that we can't use Unix time here (ie time()) because Unix time is a non-linear
// representation of time. That is, when a leap second occurs, Unix time doesn't
// increment for that particular second, so performing duration calculations across
// leap seconds produces results that would disagree with a stopwatch running over
// the same period (by a magnitude of the number of leap seconds that occurred during
// that period).
//
// Instead we use the C++ utc_clock which performs duration math accurately.

inline Instant Current() {
    using namespace std::chrono;
    using namespace date;
    
    const time_point<utc_clock> now = utc_clock::now();
    const microseconds us = duration_cast<microseconds>(now-Epoch);
    return AbsoluteBit | (Instant)us.count();
}

// DurationAbsolute: Commenting-out for now because we should use the chrono APIs / clock_utc for absolute times
//template <typename T_Duration=std::chrono::microseconds>
//static constexpr T_Duration DurationAbsolute(const Time::Instant& t) {
//    using namespace std::chrono;
//    assert(Absolute(t));
//    const microseconds us(t & ~Time::AbsoluteBit);
//    return duration_cast<T_Duration>(us);
//}

template <typename T_Duration=std::chrono::microseconds>
static constexpr T_Duration DurationRelative(const Time::Instant& t) {
    using namespace std::chrono;
    assert(!Absolute(t));
    const microseconds us(t);
    return duration_cast<T_Duration>(us);
}

} // namespace Time

namespace std::chrono {

template <typename T_Clock>
auto clock_cast(const Time::Instant& t) {
    using namespace std::chrono;
    using namespace date;
    
    // `t` must be an absolute time
    assert(Time::Absolute(t));
    
    const microseconds us(t & ~Time::AbsoluteBit);
    return clock_cast<T_Clock>(Time::Epoch+us);
}

} // std::chrono
