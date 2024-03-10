#pragma once
#include <chrono>
#include <cassert>
#include "date/date.h"
#include "date/tz.h"
#include "Time.h"

namespace Time {

// Epoch: 2022-01-01 00:00:00 +0000
static constexpr std::chrono::time_point<date::utc_clock> Epoch(std::chrono::seconds(1640995227));

struct Clock {
    template<typename T>
    using _TimePoint = std::chrono::time_point<Clock, T>;
    
    using rep = TicksS64;
    using period = Time::TicksPeriod;
    using duration = std::chrono::duration<rep, period>;
    using time_point = _TimePoint<duration>;
    
    static const bool is_steady = true;
    
    static time_point now() {
        const duration ticks(std::chrono::duration_cast<duration>(date::utc_clock::now()-Epoch));
        return time_point(ticks);
    }
    
    template<
    typename T_DurationSrc,
    typename T_DurationDst = std::common_type_t<T_DurationSrc, std::chrono::microseconds>
    >
    static _TimePoint<T_DurationDst>
    from_utc(const date::utc_time<T_DurationSrc>& x) noexcept {
        const T_DurationDst d(std::chrono::duration_cast<T_DurationDst>(x - Time::Epoch));
        return _TimePoint<T_DurationDst>(d);
    }
    
    template<
    typename T_DurationSrc,
    typename T_DurationDst = std::common_type_t<T_DurationSrc, std::chrono::microseconds>
    >
    static date::utc_time<T_DurationDst>
    to_utc(const _TimePoint<T_DurationSrc>& x) noexcept {
        const T_DurationDst d(std::chrono::duration_cast<T_DurationDst>(x.time_since_epoch()));
        return Time::Epoch + d;
    }
    
    template<
    typename T_DurationSrc,
    typename T_DurationDst = std::common_type_t<T_DurationSrc, std::chrono::microseconds>
    >
    static _TimePoint<T_DurationDst>
    from_sys(const date::sys_time<T_DurationSrc>& x) noexcept {
        return from_utc(date::utc_clock::from_sys(x));
    }
    
    template<
    typename T_DurationSrc,
    typename T_DurationDst = std::common_type_t<T_DurationSrc, std::chrono::microseconds>
    >
    static date::sys_time<T_DurationDst>
    to_sys(const _TimePoint<T_DurationSrc>& x) noexcept {
        return date::utc_clock::to_sys(to_utc(x));
    }
    
    template<typename T_DurationSrc>
    static Time::Instant TimeInstantFromTimePoint(const _TimePoint<T_DurationSrc>& x) {
        // We can only represent values after our epoch
        // (It's possible for time_points to to be before our epoch because rep == Time::Us,
        // and Time::Us is a signed value which could be negative.)
        assert(x.time_since_epoch().count() >= 0);
        const duration ticks(std::chrono::duration_cast<duration>(x.time_since_epoch()));
        return AbsoluteBit | (Time::Instant)ticks.count();
    }
    
    static time_point TimePointFromTimeInstant(Time::Instant t) {
        // `t` must be an absolute time
        assert(Time::Absolute(t));
        const duration ticks(t & ~Time::AbsoluteBit);
        return time_point(ticks);
    }
    
    static duration DurationFromTimeInstant(Time::Instant t) {
        // `t` must be a relative time
        assert(!Time::Absolute(t));
        return duration(t);
    }
    
    static duration DurationFromTicks(TicksU64 x) {
        return duration(x);
    }
    
    static TicksU64 TicksFromDuration(duration x) {
        return x.count();
    }
};

} // namespace Time
