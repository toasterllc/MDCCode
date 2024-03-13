#pragma once
#include <vector>
#include <chrono>
#include <iomanip>
#include <map>
#include "date/date.h"
#include "date/tz.h"
#include "Calendar.h"
#include "Code/Shared/Time.h"
#include "Code/Shared/Clock.h"
#include "Code/Shared/MSP.h"
#include "Toastbox/Cast.h"
#include "Toastbox/Util.h"

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
    
    static std::string StringFromUnit(const Unit& x) {
        switch (x) {
        case Unit::Seconds: return "seconds";
        case Unit::Minutes: return "minutes";
        case Unit::Hours:   return "hours";
        case Unit::Days:    return "days";
        default:            throw Toastbox::RuntimeError("invalid unit: %ju", (uintmax_t)x);
        }
    }

    static Unit UnitFromString(std::string x) {
        for (auto& c : x) c = std::tolower(c);
             if (x == "seconds") return Unit::Seconds;
        else if (x == "minutes") return Unit::Minutes;
        else if (x == "hours")   return Unit::Hours;
        else if (x == "days")    return Unit::Days;
        else                     throw Toastbox::RuntimeError("invalid unit: %s", x.c_str());
    }
    
    float value;
    Unit unit;
};

inline Duration DurationFromString(std::string_view x) {
    const auto parts = Toastbox::String::Split(x, " ");
    if (parts.size() != 2) throw Toastbox::RuntimeError("invalid duration: %s", std::string(x).c_str());
    return {
        .value = std::max(0.f, Toastbox::FloatForStr<float>(parts[0])),
        .unit = Duration::UnitFromString(parts[1]),
    };
}

inline std::string StringFromDuration(const Duration& x) {
    return std::to_string(x.value) + " " + Duration::StringFromUnit(x.unit);
}

inline std::chrono::seconds SecondsFromDuration(const Duration& x) {
    #warning TODO: how does this handle overflow? how do we want to handle overflow -- throw?
    switch (x.unit) {
    case Duration::Unit::Seconds: return std::chrono::seconds((int64_t)x.value);
    case Duration::Unit::Minutes: return std::chrono::minutes((int64_t)x.value);
    case Duration::Unit::Hours:   return std::chrono::hours((int64_t)x.value);
    case Duration::Unit::Days:    return date::days((int64_t)x.value);
    default:                      abort();
    }
}

inline Duration DurationFromSeconds(std::chrono::seconds x) {
    constexpr std::chrono::seconds Day    = date::days(1);
    constexpr std::chrono::seconds Hour   = std::chrono::hours(1);
    constexpr std::chrono::seconds Minute = std::chrono::minutes(1);
    constexpr std::chrono::seconds Second = std::chrono::seconds(1);
    if (x >= Day)    return { (float)x.count() / Day.count(),    Duration::Unit::Days };
    if (x >= Hour)   return { (float)x.count() / Hour.count(),   Duration::Unit::Hours };
    if (x >= Minute) return { (float)x.count() / Minute.count(), Duration::Unit::Minutes };
                     return { (float)x.count() / Second.count(), Duration::Unit::Seconds };
}

inline Ticks TicksForDuration(const Duration& x) {
    return SecondsFromDuration(x);
}

inline std::string StringFromFloat(float x, int maxDecimalPlaces=1) {
    std::stringstream ss;
    ss << std::fixed << std::setprecision(maxDecimalPlaces) << x;
    // Erase trailing zeroes
    std::string str = ss.str();
    for (auto it=str.end()-1; it!=str.begin(); it--) {
        if (std::isdigit(*it)) {
            if (*it == '0') {
                it = str.erase(it);
            } else {
                break;
            }
        } else {
            // Assume this is the (localized) decimal point
            it = str.erase(it);
            break;
        }
    }
    return str;
}

inline float FloatFromString(std::string_view x) {
    return Toastbox::FloatForStr<float>(x);
}

inline std::string _StringForDurationRange(std::chrono::seconds xmin, std::chrono::seconds xmax,
    std::chrono::seconds unit, std::string_view unitName) {
    const uint64_t min = xmin.count() / unit.count();
    const uint64_t max = xmax.count() / unit.count();
    std::stringstream ss;
    if (min == max) {
        ss << min << " " << unitName;
        if (min != 1) ss << "s";
    } else {
        ss << min << " – " << max << " " << unitName;
        if (max != 1) ss << "s";
    }
    return ss.str();
}

inline std::string StringForDurationRange(std::chrono::seconds min, std::chrono::seconds max) {
    constexpr std::chrono::seconds Year = date::days(365);
    constexpr std::chrono::seconds Month = date::days(30);
    constexpr std::chrono::seconds Day = date::days(1);
    std::string title;
    if (min>2*Year && max>2*Year) {
        return _StringForDurationRange(min, max, Year, "year");
    } else if (min>2*Month && max>2*Month) {
        return _StringForDurationRange(min, max, Month, "month");
    } else {
        return _StringForDurationRange(min, max, Day, "day");
    }
}

inline std::string _StringForDuration(std::chrono::seconds sec,
    std::chrono::seconds unit, std::string_view unitName) {
    const uint64_t x = sec.count() / unit.count();
    return std::to_string(x) + " " + std::string(unitName) + (x != 1 ? "s" : "");
}

inline std::string StringForDuration(std::chrono::seconds x) {
    constexpr std::chrono::seconds Year = date::days(365);
    constexpr std::chrono::seconds Month = date::days(30);
    constexpr std::chrono::seconds Day = date::days(1);
    if (x > 2*Year) {
        return _StringForDuration(x, Year, "year").c_str();
    } else if (x > 2*Month) {
        return _StringForDuration(x, Month, "month").c_str();
    } else {
        return _StringForDuration(x, Day, "day").c_str();
    }
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
template<typename T_ZonedTime>
inline uint8_t _LeapYearPhase(const T_ZonedTime& tp) {
    using namespace std::chrono;
    const auto days = floor<date::days>(tp.get_local_time());
    const auto time = floor<seconds>(tp.get_local_time())-days;
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

template<typename T_ZonedTime>
inline Time::Instant _TimeInstantForZonedTime(const T_ZonedTime& t) {
    const auto tpUtc = date::clock_cast<date::utc_clock>(t.get_sys_time());
    const auto tpDevice = date::clock_cast<Time::Clock>(tpUtc);
    const Time::Instant ti = Time::Clock::TimeInstantFromTimePoint(tpDevice);
    
    // Test code: a more direct version of the code above.
    // Use this version if the assert below never fails.
    {
        const auto tpDevice = date::clock_cast<Time::Clock>(t.get_sys_time());
        const Time::Instant tmp = Time::Clock::TimeInstantFromTimePoint(tpDevice);
        assert(tmp == ti);
    }
    
    return ti;
}

// _PastTime(): returns a time_point for most recent past occurrence of `timeOfDay`
template<typename T_ZonedTime>
inline T_ZonedTime _PastTime(
    const T_ZonedTime& now,
    Calendar::TimeOfDay timeOfDay) {
    
    const auto midnight = floor<date::days>(now.get_local_time());
    const auto t = midnight+timeOfDay;
    const date::local_seconds sec = (t<now.get_local_time() ? t : t-date::days(1));
    return { now.get_time_zone(), sec };
}

// _PastTime(): returns a time_point for most recent past occurrence of `timeOfDay`
template<typename T_ZonedTime>
inline T_ZonedTime _PastDayOfWeek(
    const T_ZonedTime& now,
    Calendar::TimeOfDay timeOfDay,
    Calendar::DaysOfWeek daysOfWeek) {
    
    // Find the most recent time+day combo that's both in the past, and whose day is in x.DaysOfWeek.
    // (Eg the current day might be in x.DaysOfWeek, but if `time` for the current day is in the future,
    // then it doesn't qualify.)
    const date::local_days midnight = floor<date::days>(now.get_local_time());
    date::local_days day = midnight;
    date::local_seconds tp;
    for (;;) {
        tp = day+timeOfDay;
        // If `tp` is in the past and `day` is in x.DaysOfWeek, we're done
        if (tp<now.get_local_time() && DaysOfWeekGet(daysOfWeek, Calendar::DayOfWeek(day))) {
            break;
        }
        day -= date::days(1);
    }
    return { now.get_time_zone(), tp };
}

// _PastTime(): returns a time_point for most recent past occurrence of `timeOfDay`
template<typename T_ZonedTime>
inline T_ZonedTime _PastDayOfYear(
    const T_ZonedTime& now,
    Calendar::TimeOfDay timeOfDay,
    Calendar::DayOfYear dayOfYear) {
    
    // Determine if doy's month+day of the current year is in the past.
    // If it's in the future, subtract one year and use that.
    const date::year nowYear = date::year_month_day(floor<date::days>(now.get_local_time())).year();
    auto tp = date::local_days{ nowYear / dayOfYear.month() / dayOfYear.day() } + timeOfDay;
    if (tp >= now.get_local_time()) {
        tp = date::local_days{ (nowYear-date::years(1)) / dayOfYear.month() / dayOfYear.day() } + timeOfDay;
        // Logic error if tp is still in the future, even after subtracting a year
        assert(tp < now.get_local_time());
    }
    return { now.get_time_zone(), tp };
}

// _DaysOfWeekBitfield(): Generate the days bitfield by advancing `daysOfWeek`
// backwards until we hit whatever day of week that `tp` is.
template<typename T_ZonedTime>
inline uint8_t _DaysOfWeekBitfield(const T_ZonedTime& tp, Calendar::DaysOfWeek daysOfWeek) {
    const date::local_days day = floor<date::days>(tp.get_local_time());
    uint8_t days = daysOfWeek.x;
    for (Calendar::DayOfWeek i=Calendar::DayOfWeek(0); i!=Calendar::DayOfWeek(day); i--) {
        days = _DaysOfWeekAdvance(days, -1);
    }
    // Low bit of `days` should be set, otherwise it's a logic bug
    assert(days & 1);
    return days;
}

// _Repeat(): necessary to work around a Clang bug that emits a invalid error when instantiating a MSP::Repeat
// in _EventsCreate() ("Field designator (null) does not refer to any field in type Repeat")
inline MSP::Repeat _Repeat(MSP::Repeat::Type type, uint8_t arg=0) {
    return MSP::Repeat{
        .type = type,
        .Daily = { arg },
    };
}

template<typename T_ZonedTime>
inline std::vector<MSP::Triggers::RepeatEvent> _EventsCreate(
    const T_ZonedTime& now,
    MSP::Triggers::Event::Type type,
    Calendar::TimeOfDay timeOfDay, const Repeat* repeat, uint8_t idx) {
    
    using namespace std::chrono;
    const T_ZonedTime pastTimeOfDay = _PastTime(now, timeOfDay);
    
    // Handle non-repeating events
    if (!repeat) {
        return { MSP::Triggers::RepeatEvent{
            MSP::Triggers::Event{
                .time = _TimeInstantForZonedTime(pastTimeOfDay),
                .type = type,
                .idx = idx,
            },
            .repeat = _Repeat(MSP::Repeat::Type::Never),
        }};
    }
    
    switch (repeat->type) {
    case Repeat::Type::Daily:
        return { MSP::Triggers::RepeatEvent{
            MSP::Triggers::Event{
                .time = _TimeInstantForZonedTime(pastTimeOfDay),
                .type = type,
                .idx = idx,
            },
            .repeat = _Repeat(MSP::Repeat::Type::Daily, 1),
        }};
    
    case Repeat::Type::DaysOfWeek: {
        // If no days are selected, dont' return any events
        if (Calendar::DaysOfWeekEmpty(repeat->DaysOfWeek)) return {};
        
        const T_ZonedTime tp = _PastDayOfWeek(now, timeOfDay, repeat->DaysOfWeek);
        // Create the DaysOfWeek bitfield that's aligned to whatever day of
        // the week `tp` is.
        // This is necessary because the time that we return and the days
        // bitfield need to be aligned so that they represent the same day.
        const uint8_t days = _DaysOfWeekBitfield(tp, repeat->DaysOfWeek);
        
        return { MSP::Triggers::RepeatEvent{
            MSP::Triggers::Event{
                .time = _TimeInstantForZonedTime(tp),
                .type = type,
                .idx = idx,
            },
            .repeat = _Repeat(MSP::Repeat::Type::Weekly, days),
        }};
    }
    
    case Repeat::Type::DaysOfYear: {
        const auto daysOfYear = Calendar::VectorFromDaysOfYear(repeat->DaysOfYear);
        std::vector<MSP::Triggers::RepeatEvent> events;
        for (Calendar::DayOfYear doy : daysOfYear) {
            // Determine if doy's month+day of the current year is in the past.
            // If it's in the future, subtract one year and use that.
            const T_ZonedTime tp = _PastDayOfYear(now, timeOfDay, doy);
            events.push_back({
                MSP::Triggers::Event{
                    .time = _TimeInstantForZonedTime(tp),
                    .type = type,
                    .idx = idx,
                },
                .repeat = _Repeat(MSP::Repeat::Type::Yearly, _LeapYearPhase(tp)),
            });
        }
        return events;
    }
    
    case Repeat::Type::DayInterval: {
        const uint8_t interval = Toastbox::Cast<decltype(MSP::Repeat::Daily.interval)>(repeat->DayInterval.count());
        return { MSP::Triggers::RepeatEvent{
            MSP::Triggers::Event{
                .time = _TimeInstantForZonedTime(pastTimeOfDay),
                .type = type,
                .idx = idx,
            },
            .repeat = _Repeat(MSP::Repeat::Type::Daily, interval),
        }};
    }
    
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
        if (x.schedule.timeRange.end > x.schedule.timeRange.start) {
            // Doesn't cross midnight: eg 9am-5pm
            return x.schedule.timeRange.end-x.schedule.timeRange.start;
        } else {
            // Crosses midnight; eg: 11pm-4am
            return x.schedule.timeRange.end + (date::days(1) - x.schedule.timeRange.start);
        }
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
// Returns nullptr if motion is always enabled and `maxTriggerCount` is disabled.
// If `maxTriggerCount` is enabled, the Repeat is required by MSPApp to reset the
// trigger count daily at midnight.
template<typename T>
const Repeat* _MotionRepeat(const T& x) {
    if (_MotionAlwaysEnabled(x) && !x.constraints.maxTriggerCount.enable) return nullptr;
    return &x.schedule.repeat;
}

inline void _AddEvents(MSP::Triggers& triggers, const std::vector<MSP::Triggers::RepeatEvent>& events) {
    const size_t eventsRem = std::size(triggers.repeatEvent)-triggers.repeatEventCount;
    if (events.size() > eventsRem) {
        throw Toastbox::RuntimeError("too many events");
    }
    std::copy(events.begin(), events.end(), triggers.repeatEvent+triggers.repeatEventCount);
    triggers.repeatEventCount += events.size();
}

inline MSP::DSTPhase _DSTPhaseCreate(std::vector<date::sys_seconds> tps) {
    using namespace std::chrono;
    assert(!tps.empty());
    // Ensure that weren't given more timepoints than the number of transitions we can support.
    // +1 because N+1 timepoints == N transitions
    assert(tps.size() <= MSP::DSTPhase::PhaseCount+1);
    
    MSP::DSTPhase phase = {};
    std::optional<date::sys_seconds> tprev;
    for (auto t : tps) {
        printf("Halla: %s\n", Calendar::TimestampString(
            Time::Clock::TimeInstantFromTimePoint(Time::Clock::from_sys(t))).c_str());
        
        if (tprev) {
            const seconds deltaSec = t-*tprev;
            const date::days deltaDays = duration_cast<date::days>(deltaSec);
            assert(deltaDays == deltaSec); // Ensure a lossless conversion; ie deltaSec must be an even multiple of days
            const date::days p = deltaDays - date::days(365);
            assert(p.count() >= MSP::DSTPhase::PhaseMin);
            assert(p.count() <= MSP::DSTPhase::PhaseMax);
            phase.push(p.count());
        }
        tprev = t;
    }
    
    // If tps.size() < `MSP::DSTPhase::PhaseCount+1`, then we need to right-shift phase.u64 so that the
    // first phase is placed at the very right of phase.u64.
    const size_t phaseCount = tps.size()-1;
    for (size_t i=0; i<MSP::DSTPhase::PhaseCount-phaseCount; i++) phase.push(0);
    return phase;
}

template<typename T_ZonedTime>
inline void _DSTEventsCreate(const T_ZonedTime& now, MSP::Triggers& t) {
    using namespace std::chrono;
    
    const date::time_zone& tz = *now.get_time_zone();
    
    // Create DSTEvents
    // TransitionTimepointCount: the number of timepoints that each vector in `transitions` should be filled with.
    // +1 because the first time will populate Event.time, while the remaining times will populate the phase.
    constexpr size_t TransitionTimepointCount = MSP::DSTPhase::PhaseCount+1;
    
    printf("now: %s\n", Calendar::TimestampString(
        Time::Clock::TimeInstantFromTimePoint(Time::Clock::from_sys(date::floor<seconds>(now.get_sys_time())))).c_str());
    
    const date::sys_seconds nowSys = date::floor<minutes>(now.get_sys_time());
    const date::sys_seconds dayMax = nowSys + date::days(365*(TransitionTimepointCount+1));
    date::sys_seconds day = nowSys - date::days(365) - date::days(1);
    std::chrono::seconds offPrev = tz.get_info(day).offset;
    std::map<std::chrono::seconds, std::vector<date::sys_seconds>> transitions;
    while (day < dayMax) {
        day += date::days(1);
        const date::sys_info dayInfo = tz.get_info(day);
        
//        printf("%ju offset = %jd\n", (uintmax_t)day.time_since_epoch().count(), (intmax_t)dayInfo.offset.count());
        
        if (dayInfo.offset != offPrev) {
            date::sys_seconds t = day;
            for (;;) {
                const date::sys_seconds tp = t;
                t -= std::chrono::minutes(1);
                const date::sys_info tInfo = tz.get_info(t);
                if (tInfo.offset != dayInfo.offset) {
                    const std::chrono::seconds delta = tInfo.offset - dayInfo.offset;
                    auto& vec = transitions[delta];
                    if (vec.size() >= TransitionTimepointCount) goto full; // Never let a single vector exceed MSP::DSTPhase::Count
                    
                    printf("Transition point: %s (delta: %jd minutes)\n", Calendar::TimestampString(
                        Time::Clock::TimeInstantFromTimePoint(Time::Clock::from_sys(tp))).c_str(), (intmax_t)delta.count());
                    
                    vec.push_back(tp);
//                    printf("Found transition point: %ju (delta: %jd minutes)\n", (uintmax_t)transitionTime.time_since_epoch().count(), (intmax_t)delta.count());
                    break;
                }
            }
            offPrev = dayInfo.offset;
//            printf("Found transition: ");
        }
    }
full:
    
    // We should either have 0 deltas (for places that don't have DST) or 2 deltas
    // (eg +1 hour / -1 hour, or some rare places that do +30 minutes / -30 minutes).
    assert(transitions.size()==0 || transitions.size()==2);
    
    if (transitions.size() == 2) {
        auto transitionIt = transitions.begin();
        for (size_t i=0; i<2; i++, transitionIt++) {
            const std::chrono::seconds adjustmentSec = transitionIt->first;
            const Ticks adjustmentTicks = adjustmentSec;
            const std::vector<date::sys_seconds>& tps = transitionIt->second;
            const auto tp = date::clock_cast<Time::Clock>(tps.front());
            
            printf("DSTEvent.time = %s (adj: %jd)\n", Calendar::TimestampString(
                Time::Clock::TimeInstantFromTimePoint(tp)).c_str(), (intmax_t)adjustmentTicks.count());
            
            MSP::Triggers::DSTEvent& dstEvent = t.dstEvent[i];
            dstEvent = MSP::Triggers::DSTEvent{
                MSP::Triggers::Event{
                    .time = Time::Clock::TimeInstantFromTimePoint(tp),
                    .type = MSP::Triggers::Event::Type::DST,
                    .idx = (uint8_t)i,
                },
                .phase = _DSTPhaseCreate(tps),
                .adjustmentTicks = Toastbox::Cast<decltype(MSP::Triggers::DSTEvent::adjustmentTicks)>(adjustmentTicks.count()),
            };
        }
        
        // The DSTEvent that occurs first will adjust the time of the DSTEvent that occurs second.
        //
        // We don't want that behavior, so we subtract the `adjustmentTicks` from the DSTEvent
        // that occurs second, to counteract the addition of `adjustmentTicks` that the first
        // DSTEvent will perform.
        //
        // This is a little ugly but it's the most elegant solution we've found so far.
        // An alternative is to implement DSTEvent logic such that they don't affect other
        // DSTEvents, but that could cause events in the event array to become out-of-order,
        // since we'd be adjusting the time of some events but not others.
        
        // If dstEvent[1] occurs second:
        if (t.dstEvent[1].time > t.dstEvent[0].time) {
            t.dstEvent[1].time -= t.dstEvent[0].adjustmentTicks;
        
        // If dstEvent[0] occurs second:
        } else if (t.dstEvent[0].time > t.dstEvent[1].time) {
            t.dstEvent[0].time -= t.dstEvent[1].adjustmentTicks;
        
        } else {
            // Shouldn't be possible
            abort();
        }
        
        t.dstEventCount = 2;
    }
}

inline MSP::Triggers Convert(const Triggers& triggers) {
    using namespace std::chrono;
    
    const date::time_zone& tz = *date::current_zone();
    const date::zoned_time now(&tz, std::chrono::system_clock::now());
    
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
                const auto events = _EventsCreate(now,
                    MSP::Triggers::Event::Type::TimeTrigger,
                    x.schedule.time, &x.schedule.repeat, t.timeTriggerCount);
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
                const auto events = _EventsCreate(now,
                    MSP::Triggers::Event::Type::MotionEnable,
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
    
    _DSTEventsCreate(now, t);
    
    Serialize(t.source, triggers);
    return t;
}

} // namespace DeviceSettings
} // namespace MDCStudio
