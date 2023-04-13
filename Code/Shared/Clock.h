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
    template <typename T>
    using _TimePoint = std::chrono::time_point<Clock, T>;
    
    using rep = Time::Us;
    using period = std::micro;
    using duration = std::chrono::duration<rep, period>;
    using time_point = _TimePoint<duration>;
    
    static const bool is_steady = true;
    
    static time_point now() {
        using namespace std::chrono;
        const microseconds us(date::utc_clock::now()-Epoch);
        return time_point(us);
    }
    
    template<class Duration>
    static _TimePoint<std::common_type_t<Duration, std::chrono::seconds>>
    from_utc(const date::utc_time<Duration>& x) noexcept {
        return time_point(x - Time::Epoch);
    }
    
    template<class Duration>
    static date::utc_time<std::common_type_t<Duration, std::chrono::seconds>>
    to_utc(const _TimePoint<Duration>& x) noexcept {
        return Time::Epoch + x.time_since_epoch();
    }
    
    template<class Duration>
    static _TimePoint<std::common_type_t<Duration, std::chrono::seconds>>
    from_sys(const date::sys_time<Duration>& x) noexcept {
        return from_utc(date::utc_clock::from_sys(x));
    }
    
    template<class Duration>
    static date::sys_time<std::common_type_t<Duration, std::chrono::seconds>>
    to_sys(const _TimePoint<Duration>& x) noexcept {
        return date::utc_clock::to_sys(to_utc(x));
    }
    
    static Time::Instant TimeInstantFromTimePoint(time_point x) {
        return AbsoluteBit | x.time_since_epoch().count();
    }
    
    static time_point TimePointFromTimeInstant(Time::Instant t) {
        using namespace std::chrono;
        // `t` must be an absolute time
        assert(Time::Absolute(t));
        const microseconds us(t & ~Time::AbsoluteBit);
        return time_point(us);
    }
    
    static duration DurationFromTimeInstant(Time::Instant t) {
        using namespace std::chrono;
        // `t` must be a relative time
        assert(!Time::Absolute(t));
        return duration(t);
    }
};

} // namespace Time


//namespace date {
//    template<>
//    struct clock_time_conversion<utc_clock, Time::Clock>
//    {
//        template<class Duration>
//        std::chrono::time_point<Time::Clock, Duration>
//        operator()(const std::chrono::time_point<Time::Clock, Duration>& t) const {
//            return Time::Epoch + t.time_since_epoch();
//        }
//    };
//    
//    template<>
//    struct clock_time_conversion<Time::Clock, utc_clock>
//    {
//        template<class Duration>
//        std::chrono::time_point<utc_clock, Duration>
//        operator()(const std::chrono::time_point<utc_clock, Duration>& t) const {
//            return t.time_since_epoch() - Time::Epoch;
//        }
//    };
//    
////    template<>
////    struct clock_time_conversion<std::chrono::system_clock, Time::Clock>
////    {
////        template<class Duration>
////        std::chrono::time_point<Time::Clock, Duration>
////        operator()(const std::chrono::time_point<Time::Clock, Duration>& t) const {
////            return {};
////        }
////    };
//}

//
//
//// Current(): returns the current time instant
////
//// Note that we can't use Unix time here (ie time()) because Unix time is a non-linear
//// representation of time. That is, when a leap second occurs, Unix time doesn't
//// increment for that particular second, so performing duration calculations across
//// leap seconds produces results that would disagree with a stopwatch running over
//// the same period (by a magnitude of the number of leap seconds that occurred during
//// that period).
////
//// Instead we use the C++ utc_clock which performs duration math accurately.
//
//inline Instant Current() {
//    using namespace std::chrono;
//    using namespace date;
//    
//    const time_point<utc_clock> now = utc_clock::now();
//    const microseconds us = duration_cast<microseconds>(now-Epoch);
//    return AbsoluteBit | (Instant)us.count();
//}
//
//// DurationAbsolute: Commenting-out for now because we should use the chrono APIs / clock_utc for absolute times
////template <typename T_Duration=std::chrono::microseconds>
////static constexpr T_Duration DurationAbsolute(const Time::Instant& t) {
////    using namespace std::chrono;
////    assert(Absolute(t));
////    const microseconds us(t & ~Time::AbsoluteBit);
////    return duration_cast<T_Duration>(us);
////}
//
//template <typename T_Duration=std::chrono::microseconds>
//static constexpr T_Duration DurationRelative(const Time::Instant& t) {
//    using namespace std::chrono;
//    assert(!Absolute(t));
//    const microseconds us(t);
//    return duration_cast<T_Duration>(us);
//}
//
//} // namespace Time
//
//namespace std::chrono {
//
//template <typename T_Clock>
//auto clock_cast(const Time::Instant& t) {
//    using namespace std::chrono;
//    using namespace date;
//    
//    // `t` must be an absolute time
//    assert(Time::Absolute(t));
//    
//    const microseconds us(t & ~Time::AbsoluteBit);
//    return clock_cast<T_Clock>(Time::Epoch+us);
//}
//
//} // std::chrono
