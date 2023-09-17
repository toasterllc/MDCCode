#pragma once
#include <vector>
#include <chrono>
#include "date/date.h"
#include "date/tz.h"
#include "Calendar.h"
#include "Code/Shared/Time.h"
#include "Code/Shared/Clock.h"
#include "Toastbox/Cast.h"

namespace MDCStudio {
namespace DeviceSettings {

using Ticks = Time::Clock::duration;
using Days = std::chrono::duration<uint32_t, std::ratio<86400>>;
using DayInterval = Days;

struct [[gnu::packed]] Repeat {
    enum class Type : uint8_t {
        Daily,
        DaysOfWeek,
        DaysOfYear,
        DayInterval,
    };
    
    Type type;
    union {
        Calendar::DaysOfWeek DaysOfWeek;
        Calendar::DaysOfYear DaysOfYear;
        DayInterval DayInterval;
    };
};

struct [[gnu::packed]] Duration {
    enum class Unit : uint8_t {
        Seconds,
        Minutes,
        Hours,
        Days,
    };
    
    float value;
    Unit unit;
};

inline Ticks TicksForDuration(const Duration& x) {
    #warning TODO: how does this handle overflow? how do we want to handle overflow -- throw?
    switch (x.unit) {
    case Duration::Unit::Seconds: return std::chrono::seconds((long)x.value);
    case Duration::Unit::Minutes: return std::chrono::minutes((long)x.value);
    case Duration::Unit::Hours:   return std::chrono::hours((long)x.value);
    case Duration::Unit::Days:    return date::days((long)x.value);
    default:                      abort();
    }
    
//    #warning TODO: how does this handle overflow? do we want to clamp or throw?
//    return std::chrono::seconds((long)_MsForDuration(x));
//    return std::clamp(_MsForDuration(x), 0.f, (float)UINT32_MAX);
}

struct [[gnu::packed]] Capture {
    uint16_t count;
    Duration interval;
    bool ledFlash;
};

struct [[gnu::packed]] Trigger {
    enum class Type : uint8_t {
        Time,
        Motion,
        Button,
    };
    
    Type type = Type::Time;
    
    union {
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                Calendar::TimeOfDay time;
                Repeat repeat;
            } schedule;
            
            Capture capture;
        } time;
        
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    Calendar::TimeOfDay start;
                    Calendar::TimeOfDay end;
                } timeRange;
                
                Repeat repeat;
            } schedule;
            
            Capture capture;
            
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    Duration duration;
                } suppressDuration;
                
                struct [[gnu::packed]] {
                    bool enable;
                    uint16_t count;
                } maxTriggerCount;
            } constraints;
        } motion;
        
        struct [[gnu::packed]] {
            Capture capture;
        } button;
    };
};

struct [[gnu::packed]] Triggers {
    Trigger triggers[32] = {};
    uint8_t count = 0;
};

struct [[gnu::packed]] TriggersSerialized {
    static constexpr uint16_t Version = 0;
    static constexpr size_t Size = 256;
    union {
        struct [[gnu::packed]] {
            uint16_t version;
            uint8_t payload[Size-2];
        };
        
        uint8_t data[Size] = {};
    };
};
static_assert(sizeof(TriggersSerialized) == TriggersSerialized::Size);

template<typename T>
std::vector<uint8_t> _Compress(T begin, T end) {
    std::vector<uint8_t> x;
    for (auto it=begin; it!=end;) {
        if (*it) {
            x.push_back(*it);
            it++;
        } else {
            uint8_t z = 0;
            while (z!=0xff && it!=end && !*it) {
                z++;
                it++;
            }
            x.push_back(0);
            x.push_back(z);
        }
    }
    return x;
}

template<typename T>
std::vector<uint8_t> _Decompress(T begin, T end) {
    std::vector<uint8_t> x;
    for (auto it=begin; it!=end;) {
        if (*it) {
            x.push_back(*it);
            it++;
        } else {
            it++;
            if (it == end) break; // Allow trailing zeroes
            x.insert(x.end(), *it, 0);
            it++;
        }
    }
    return x;
}

template<typename T>
inline void Serialize(T& data, const Triggers& x) {
    static_assert(sizeof(data) == sizeof(TriggersSerialized));
    
    TriggersSerialized s = {
        .version = TriggersSerialized::Version,
    };
    
    // Triggers -> TriggersSerialized
    {
        auto d = _Compress((uint8_t*)&x, (uint8_t*)&x+sizeof(x));
        if (d.size() > sizeof(s.payload)) {
            throw Toastbox::RuntimeError("data doesn't fit in TriggersSerialized (length: %ju, capacity: %ju)",
                (uintmax_t)d.size(), (uintmax_t)sizeof(s.payload));
        }
        memcpy(s.payload, d.data(), d.size());
    }
    
    // TriggersSerialized -> data
    {
        memcpy(&data, &s, sizeof(s));
    }
}

template<typename T>
inline void Deserialize(Triggers& x, const T& data) {
    static_assert(sizeof(data) == sizeof(TriggersSerialized));
    
    TriggersSerialized s;
    
    // data -> TriggersSerialized
    {
        memcpy(&s, &data, sizeof(data));
        
        if (s.version != TriggersSerialized::Version) {
            throw Toastbox::RuntimeError("TriggersSerialized version invalid (expected: %ju, got: %ju)",
                (uintmax_t)TriggersSerialized::Version, (uintmax_t)s.version);
        }
    }
    
    // TriggersSerialized -> Triggers
    {
        auto d = _Decompress(s.payload, s.payload+sizeof(s.payload));
        if (d.size() != sizeof(x)) {
            throw Toastbox::RuntimeError("deserialized data length doesn't match sizeof(Triggers) (expected: %ju, got: %ju)",
                (uintmax_t)sizeof(x), (uintmax_t)d.size());
        }
        memcpy(&x, d.data(), d.size());
        if (x.count > std::size(x.triggers)) {
            throw Toastbox::RuntimeError("invalid deserialized trigger count (got: %ju, max: %ju)",
                (uintmax_t)x.count, (uintmax_t)std::size(x.triggers));
        }
    }
}
















//template<typename T_Dst, typename T_Src>
//T_Dst _Cast(const T_Src& x) {
//    // Only support unsigned for now
//    static_assert(!std::numeric_limits<T_Src>::is_signed);
//    static_assert(!std::numeric_limits<T_Dst>::is_signed);
//    const T_Dst DstMaxValue = std::numeric_limits<T_Dst>::max();
//    if (x > DstMaxValue) {
//        throw Toastbox::RuntimeError("value too large (value: %ju, max: %ju)", (uintmax_t)x, (uintmax_t)DstMaxValue);
//    }
//    return x;
//}




//template<typename T_Dst, typename T_Src>
//T_Dst _Cast(const T_Src& x) {
//    // intmax_t -> uint32
//    constexpr T_Src SrcMinValue = std::numeric_limits<T_Src>::min();    // -big val
//    constexpr T_Src SrcMaxValue = std::numeric_limits<T_Src>::max();    // big val
//    constexpr T_Dst DstMinValue = std::numeric_limits<T_Dst>::min();    // 0
//    constexpr T_Dst DstMaxValue = std::numeric_limits<T_Dst>::max();    // smaller big val
//    
//    if constexpr (SrcMinValue < DstMinValue)
//    
//    if (x > DstMaxValue) {
//        throw Toastbox::RuntimeError("value too large (value: %ju, max: %ju)", (uintmax_t)x, (uintmax_t)DstMaxValue);
//    }
//    return x;
//}

inline MSP::Capture _Convert(const Capture& x) {
    return MSP::Capture{
        .delayTicks = Toastbox::Cast<decltype(MSP::Capture::delayTicks)>(TicksForDuration(x.interval).count()),
        .count = x.count,
        .ledFlash = x.ledFlash,
    };
}

inline uint8_t _DaysOfWeekAdvance(uint8_t x, int dir) {
    if (dir > 0) {
        // Forward (into future)
        x |= (x&0x01)<<7;
        x >>= 1;
        return x;
    } else if (dir < 0) {
        // Reverse (into past)
        x <<= 1;
        x |= ((x&0x80)>>7);
        x &= 0x7F;
        return x;
    }
    abort();
}

// _LeapYearPhase(): returns a number between [0,7] indicating the leap year
// cadence relative to `tp`. The value can be as high as 7 due to the skipped
// leap years (skipped if divisible by 100 but not by 400; eg 1900 and 2100
// aren't leap years despite being divisible by 4.)
//
// For example, to get the same date as `tp` but N years in the future:
//
//   - if _LeapYearPhase() returns 0:
//       - to add 1 year  to `tp`, add 366                 days
//       - to add 2 years to `tp`, add 366+365             days
//       - to add 3 years to `tp`, add 366+365+365         days
//       - to add 4 years to `tp`, add 366+365+365+365     days
//       - to add 5 years to `tp`, add 366+365+365+365+366 days
//
//   - if _LeapYearPhase() returns 1:
//       - to add 1 year  to `tp`, add 365                 days
//       - to add 2 years to `tp`, add 365+366             days
//       - to add 3 years to `tp`, add 365+366+365         days
//       - to add 4 years to `tp`, add 365+366+365+365     days
//       - to add 5 years to `tp`, add 365+366+365+365+365 days
//   ... and so on ...
inline uint8_t _LeapYearPhase(const date::time_zone& tz, const date::local_seconds& tp) {
    using namespace std::chrono;
    const auto days = floor<date::days>(tp);
    const auto time = tp-days;
    date::year_month_day ymd(days);
    
    // Try up to 8 years to find the next leap year.
    for (uint8_t i=0; i<8; i++) {
        const date::year_month_day ymdNext((ymd.year()+date::years(1)) / ymd.month() / ymd.day());
        const seconds delta = (date::local_days(ymdNext)+time) - (date::local_days(ymd)+time);
        const date::days days = duration_cast<date::days>(delta);
        
        switch (days.count()) {
        case 365: break;
        case 366: return i;
        default: abort();
        }
        
        ymd = ymdNext;
    }
    
    // Couldn't 
    abort();
}

// _PastTime(): returns a time_point for most recent past occurrence of `timeOfDay`
template<typename T>
inline date::local_seconds _PastTime(const T& now, Calendar::TimeOfDay timeOfDay) {
    const auto midnight = floor<date::days>(now);
    const auto t = midnight+timeOfDay;
    if (t < now) return t;
    return t-date::days(1);
}

inline Time::Instant _TimeInstantForLocalTime(const date::time_zone& tz, const date::local_seconds& tp) {
    const auto tpUtc = date::clock_cast<date::utc_clock>(tz.to_sys(tp));
    const auto tpDevice = date::clock_cast<Time::Clock>(tpUtc);
    return Time::Clock::TimeInstantFromTimePoint(tpDevice);
}

inline std::vector<MSP::Triggers::Event> _EventsCreate(MSP::Triggers::Event::Type type,
    Calendar::TimeOfDay timeOfDay, const Repeat* repeat, uint8_t idx) {
    
    using namespace std::chrono;
    const date::time_zone& tz = *date::current_zone();
    const auto now = tz.to_local(system_clock::now());
    const auto pastTimeOfDay = _PastTime(now, timeOfDay);
    
    // Handle non-repeating events
    if (!repeat) {
        return { MSP::Triggers::Event{
            .time = _TimeInstantForLocalTime(tz, pastTimeOfDay),
            .type = type,
            .repeat = { .type = MSP::Repeat::Type::Never, },
            .idx = idx,
        }};
    }
    
    switch (repeat->type) {
    case Repeat::Type::Daily:
        return { MSP::Triggers::Event{
            .time = _TimeInstantForLocalTime(tz, pastTimeOfDay),
            .type = type,
            .repeat = {
                .type = MSP::Repeat::Type::Daily,
                .Daily = { 1 },
            },
            .idx = idx,
        }};
    
    case Repeat::Type::DaysOfWeek: {
        // Find the most recent time+day combo that's both in the past, and whose day is in x.DaysOfWeek.
        // (Eg the current day might be in x.DaysOfWeek, but if `time` for the current day is in the future,
        // then it doesn't qualify.)
        const date::local_days midnight = floor<date::days>(now);
        date::local_days day = midnight;
        date::local_seconds tp;
        for (;;) {
            tp = day+timeOfDay;
            // If `tp` is in the past and `day` is in x.DaysOfWeek, we're done
            if (tp<now && DaysOfWeekGet(repeat->DaysOfWeek, Calendar::DayOfWeek(day))) {
                break;
            }
            day -= date::days(1);
        }
        
        // Generate the days bitfield by advancing x.DaysOfWeek backwards until we
        // hit whatever day of week that `day` is. This is necessary because the time
        // that we return and the days bitfield need to be aligned so that they
        // represent the same day.
        uint8_t days = repeat->DaysOfWeek.x;
        for (Calendar::DayOfWeek i=Calendar::DayOfWeek(0); i!=Calendar::DayOfWeek(day); i--) {
            days = _DaysOfWeekAdvance(days, -1);
        }
        // Low bit of `days` should be set, otherwise it's a logic bug
        assert(days & 1);
        
        return { MSP::Triggers::Event{
            .time = _TimeInstantForLocalTime(tz, tp),
            .type = type,
            .repeat = {
                .type = MSP::Repeat::Type::Weekly,
                .Weekly = { days },
            },
            .idx = idx,
        }};
    }
    
    case Repeat::Type::DaysOfYear: {
        const auto daysOfYear = Calendar::VectorFromDaysOfYear(repeat->DaysOfYear);
        std::vector<MSP::Triggers::Event> events;
        for (Calendar::DayOfYear doy : daysOfYear) {
            // Determine if doy's month+day of the current year is in the past.
            // If it's in the future, subtract one year and use that.
            const date::year nowYear = date::year_month_day(floor<date::days>(now)).year();
            auto tp = date::local_days{ nowYear / doy.month() / doy.day() } + timeOfDay;
            if (tp >= now) {
                tp = date::local_days{ (nowYear-date::years(1)) / doy.month() / doy.day() } + timeOfDay;
                // Logic error if tp is still in the future, even after subtracting a year
                assert(tp < now);
            }
            
            events.push_back({
                .time = _TimeInstantForLocalTime(tz, tp),
                .type = type,
                .repeat = {
                    .type = MSP::Repeat::Type::Yearly,
                    .Yearly = { _LeapYearPhase(tz, tp) },
                },
                .idx = idx,
            });
        }
        return events;
    }
    
    case Repeat::Type::DayInterval:
        return { MSP::Triggers::Event{
            .time = _TimeInstantForLocalTime(tz, pastTimeOfDay),
            .type = type,
            .repeat = {
                .type = MSP::Repeat::Type::Daily,
                .Daily = { Toastbox::Cast<decltype(MSP::Repeat::Daily.interval)>(repeat->DayInterval.count()) },
            },
            .idx = idx,
        }};
    
    default:
        abort();
    }
}


//template<typename T>
//std::vector<MSP::Triggers::Event> _EventsForTimeTrigger(const T& x, uint32_t idx) {
//    std::vector<MSP::Triggers::Event> events;
//    
//    return events;
//}
//
//template<typename T>
//std::vector<MSP::Triggers::Event> _EventsForMotionTrigger(const T& x, uint32_t idx) {
//    std::vector<MSP::Triggers::Event> events;
//    
//    return events;
//}

template<typename T>
bool _MotionAlwaysEnabled(const T& x) {
    return !x.schedule.timeRange.enable && x.schedule.repeat.type==Repeat::Type::Daily;
}

template<typename T>
Ticks _MotionEnableDurationTicks(const T& x) {
    // Enabled all day, every day
    if (_MotionAlwaysEnabled(x)) return {};
    
    // Enabled for part of the day
    if (x.schedule.timeRange.enable) {
        return x.schedule.timeRange.end-x.schedule.timeRange.start;
    }
    
    // Enabled all day (0:00 to 23:59)
    return date::days(1);
}

template<typename T>
Ticks _MotionSuppressTicks(const T& x) {
    if (!x.constraints.suppressDuration.enable) {
        // Suppression feature disabled
        return {};
    }
    return TicksForDuration(x.constraints.suppressDuration.duration);
}

template<typename T>
Calendar::TimeOfDay _MotionTimeOfDay(const T& x) {
    if (!x.schedule.timeRange.enable) return {}; // Midnight
    return x.schedule.timeRange.start;
}

// _MotionRepeat(): get the Repeat for a motion trigger
// Returns nullptr if motion is always supposed to be enabled
template<typename T>
const Repeat* _MotionRepeat(const T& x) {
    if (_MotionAlwaysEnabled(x)) return nullptr;
    return &x.schedule.repeat;
}

inline void _AddEvents(MSP::Triggers& triggers, const std::vector<MSP::Triggers::Event>& events) {
    const size_t eventsRem = std::size(triggers.event)-triggers.eventCount;
    if (events.size() > eventsRem) {
        throw Toastbox::RuntimeError("too many events");
    }
    std::copy(events.begin(), events.end(), triggers.event+triggers.eventCount);
    triggers.eventCount += events.size();
}

inline MSP::Triggers Convert(const Triggers& triggers) {
    MSP::Triggers t = {};
    for (auto it=std::begin(triggers.triggers); it!=std::begin(triggers.triggers)+triggers.count; it++) {
        switch (it->type) {
        case Trigger::Type::Time: {
            // Make sure there's an available slot for the trigger
            if (t.timeTriggerCount >= std::size(t.timeTrigger)) {
                throw Toastbox::RuntimeError("no remaining time triggers");
            }
            
            const auto& x = it->time;
            
            // Create events for the trigger
            {
                const auto events = _EventsCreate(MSP::Triggers::Event::Type::TimeTrigger, x.schedule.time, &x.schedule.repeat, t.timeTriggerCount);
                _AddEvents(t, events);
            }
            
            // Create trigger
            {
                t.timeTrigger[t.timeTriggerCount] = {
                    .capture = _Convert(x.capture),
                };
                t.timeTriggerCount++;
            }
            break;
        }
        
        case Trigger::Type::Motion: {
            // Make sure there's an available slot for the trigger
            if (t.motionTriggerCount >= std::size(t.motionTrigger)) {
                throw Toastbox::RuntimeError("no remaining motion triggers");
            }
            
            const auto& x = it->motion;
            
            // Create events for the trigger
            {
                const auto events = _EventsCreate(MSP::Triggers::Event::Type::MotionEnable,
                    _MotionTimeOfDay(x), _MotionRepeat(x), t.motionTriggerCount);
                _AddEvents(t, events);
            }
            
            // Create trigger
            {
                const uint16_t count = (x.constraints.maxTriggerCount.enable ? x.constraints.maxTriggerCount.count : 0);
                const Ticks durationTicks = _MotionEnableDurationTicks(x);
                const Ticks suppressTicks = _MotionSuppressTicks(x);
                
                t.motionTrigger[t.motionTriggerCount] = {
                    .capture       = _Convert(x.capture),
                    .count         = count,
                    .durationTicks = Toastbox::Cast<decltype(t.motionTrigger->durationTicks)>(durationTicks.count()),
                    .suppressTicks = Toastbox::Cast<decltype(t.motionTrigger->suppressTicks)>(suppressTicks.count()),
                };
                t.motionTriggerCount++;
            }
            break;
        }
        
        case Trigger::Type::Button: {
            // Make sure there's an available slot for the trigger
            if (t.buttonTriggerCount >= std::size(t.buttonTrigger)) {
                throw Toastbox::RuntimeError("no remaining button triggers");
            }
            
            const auto& x = it->button;
            t.buttonTrigger[t.buttonTriggerCount] = {
                .capture = _Convert(x.capture),
            };
            t.buttonTriggerCount++;
            break;
        }
        
        default: abort();
        }
    }
    
    Serialize(t.source, triggers);
    return t;
}

} // namespace DeviceSettings
} // namespace MDCStudio
