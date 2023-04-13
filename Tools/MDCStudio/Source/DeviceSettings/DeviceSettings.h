#pragma once
#include <vector>
#include <chrono>
#include "date/date.h"

namespace DeviceSettings {

namespace Calendar {

// TimeOfDay: a particular time of an unspecified day, in seconds [0,86400]
using TimeOfDay = std::chrono::duration<uint32_t>;

// DayOfWeek: a particular day of an unspecified week
using DayOfWeek = date::weekday;

// DayOfMonth: a particular day of an unspecified month [1,31]
struct [[gnu::packed]] DayOfMonth { uint8_t x; };

// MonthOfYear: a particular month of an unspecified year [1,12]
struct [[gnu::packed]] MonthOfYear { uint8_t x; };

// DayOfYear: a particular day of an unspecified year
struct [[gnu::packed]] DayOfYear {
    MonthOfYear month;
    DayOfMonth day;
};

// DaysOfWeek: a set of days of an unspecified week
struct [[gnu::packed]] DaysOfWeek { uint8_t x; };

// DaysOfMonth: a set of days of an unspecified month
struct [[gnu::packed]] DaysOfMonth { uint32_t x; };

// DaysOfYear: a set of days of an unspecified year
struct [[gnu::packed]] DaysOfYear { DaysOfMonth x[12]; };

using HHMMSS = date::hh_mm_ss<TimeOfDay>;




inline void TimeOfDayValidate(TimeOfDay x) {
    if (x.count() > 24*60*60) throw Toastbox::RuntimeError("invalid TimeOfDay: %ju", (uintmax_t)x.count());
}

inline void DayOfWeekValidate(DayOfWeek x) {
    if (!x.ok()) throw Toastbox::RuntimeError("invalid DayOfWeek: %ju", (uintmax_t)x.c_encoding());
}

inline void DayOfMonthValidate(DayOfMonth x) {
    if (x.x<1 || x.x>31) throw Toastbox::RuntimeError("invalid DayOfMonth: %ju", (uintmax_t)x.x);
}

inline void MonthOfYearValidate(MonthOfYear x) {
    if (x.x<1 || x.x>12) throw Toastbox::RuntimeError("invalid MonthOfYear: %ju", (uintmax_t)x.x);
}

inline void DayOfYearValidate(DayOfYear x) {
    MonthOfYearValidate(x.month);
    DayOfMonthValidate(x.day);
}





inline std::string StringForDayOfWeek(DayOfWeek x) {
    if (x == date::Sunday)    return "Sun";
    if (x == date::Monday)    return "Mon";
    if (x == date::Tuesday)   return "Tue";
    if (x == date::Wednesday) return "Wed";
    if (x == date::Thursday)  return "Thu";
    if (x == date::Friday)    return "Fri";
    if (x == date::Saturday)  return "Sat";
    abort();
}

inline constexpr uint8_t DaysOfWeekMask(DayOfWeek day) {
    return 1 << day.c_encoding();
}

inline bool DaysOfWeekGet(DaysOfWeek x, DayOfWeek day) {
    return x.x & DaysOfWeekMask(day);
}

inline void DaysOfWeekSet(DaysOfWeek& x, DayOfWeek day, bool y) {
    x.x &= ~DaysOfWeekMask(day);
    if (y) x.x |= DaysOfWeekMask(day);
}

inline std::vector<DayOfWeek> VectorFromDaysOfWeek(DaysOfWeek x) {
    std::vector<DayOfWeek> r;
    for (uint8_t i=0; i<7; i++) {
        const DayOfWeek d(i);
        if (x.x & DaysOfWeekMask(d)) {
            r.push_back(d);
        }
    }
    return r;
}

inline DaysOfWeek DaysOfWeekFromVector(const std::vector<DayOfWeek>& x) {
    DaysOfWeek r = {};
    for (const DayOfWeek& d : x) {
        DayOfWeekValidate(d);
        DaysOfWeekSet(r, d, true);
    }
    return r;
}







inline std::optional<DayOfMonth> DayOfMonthFromString(std::string_view x) {
    DayOfMonth y = {};
    try {
        Toastbox::IntForStr(y.x, x);
        DayOfMonthValidate(y);
    } catch (...) { return std::nullopt; }
    return y;
}

inline std::string StringFromDayOfMonth(DayOfMonth x) {
    return std::to_string(x.x);
}

inline constexpr uint32_t DaysOfMonthMask(DayOfMonth day) {
    return 1 << (day.x-1);
}

inline bool DaysOfMonthGet(DaysOfMonth x, DayOfMonth day) {
    return x.x & DaysOfMonthMask(day);
}

inline void DaysOfMonthSet(DaysOfMonth& x, DayOfMonth day, bool y) {
    x.x &= ~DaysOfMonthMask(day);
    if (y) x.x |= DaysOfMonthMask(day);
}

inline std::vector<DayOfMonth> VectorFromDaysOfMonth(DaysOfMonth x) {
    std::vector<DayOfMonth> r;
    for (DayOfMonth day={1}; day.x<=31; day.x++) {
        if (DaysOfMonthGet(x, day)) {
            r.push_back(day);
        }
    }
    return r;
}

inline DaysOfMonth DaysOfMonthFromVector(const std::vector<DayOfMonth>& x) {
    DaysOfMonth r = {};
    for (DayOfMonth day : x) {
        DayOfMonthValidate(day);
        DaysOfMonthSet(r, day, true);
    }
    return r;
}






inline std::vector<DayOfYear> VectorFromDaysOfYear(const DaysOfYear& x) {
    std::vector<DayOfYear> r;
    for (MonthOfYear m={1}; m.x<=12; m.x++) {
        const std::vector<DayOfMonth> days = VectorFromDaysOfMonth(x.x[m.x-1]);
        for (const DayOfMonth& d : days) {
            r.push_back(DayOfYear{m,d});
        }
    }
    return r;
}

inline DaysOfYear DaysOfYearFromVector(const std::vector<DayOfYear>& x) {
    DaysOfYear r = {};
    for (const DayOfYear& d : x) {
        DayOfYearValidate(d);
        DaysOfMonthSet(r.x[d.month.x-1], d.day, true);
    }
    return r;
}








struct _DateFormatterState {
    NSCalendar* cal = nil;
    NSDateFormatter* timeFormatterHH = nil;
    NSDateFormatter* timeFormatterHHMM = nil;
    NSDateFormatter* timeFormatterHHMMSS = nil;
    NSDateFormatter* dayOfYearFormatter = nil;
    bool showsAMPM = false;
    char timeSeparator = 0;
};

static _DateFormatterState _DateFormatterStateCreate() {
    _DateFormatterState x;
    x.cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    {
        x.timeFormatterHH = [[NSDateFormatter alloc] init];
        [x.timeFormatterHH setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.timeFormatterHH setCalendar:x.cal];
        [x.timeFormatterHH setTimeZone:[x.cal timeZone]];
        [x.timeFormatterHH setLocalizedDateFormatFromTemplate:@"hh"];
        [x.timeFormatterHH setLenient:true];
    }
    
    {
        x.timeFormatterHHMM = [[NSDateFormatter alloc] init];
        [x.timeFormatterHHMM setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.timeFormatterHHMM setCalendar:x.cal];
        [x.timeFormatterHHMM setTimeZone:[x.cal timeZone]];
        [x.timeFormatterHHMM setLocalizedDateFormatFromTemplate:@"hhmm"];
        [x.timeFormatterHHMM setLenient:true];
    }
    
    {
        x.timeFormatterHHMMSS = [[NSDateFormatter alloc] init];
        [x.timeFormatterHHMMSS setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.timeFormatterHHMMSS setCalendar:x.cal];
        [x.timeFormatterHHMMSS setTimeZone:[x.cal timeZone]];
        [x.timeFormatterHHMMSS setLocalizedDateFormatFromTemplate:@"hhmmss"];
        [x.timeFormatterHHMMSS setLenient:true];
    }
    
    {
        x.dayOfYearFormatter = [[NSDateFormatter alloc] init];
        [x.dayOfYearFormatter setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.dayOfYearFormatter setCalendar:x.cal];
        [x.dayOfYearFormatter setTimeZone:[x.cal timeZone]];
        [x.dayOfYearFormatter setLocalizedDateFormatFromTemplate:@"MMMd"];
        [x.dayOfYearFormatter setLenient:true];
    }
    
    NSString* dateFormat = [x.timeFormatterHHMMSS dateFormat];
    x.showsAMPM = [dateFormat containsString:@"a"];
    x.timeSeparator = ([dateFormat containsString:@":"] ? ':' : 0);
    
    return x;
}

static _DateFormatterState& _DateFormatterStateGet() {
    static _DateFormatterState x = _DateFormatterStateCreate();
    return x;
}

// 56789 -> 3:46:29 PM / 15:46:29 (depending on locale)
inline std::string StringFromTimeOfDay(TimeOfDay x) {
    const HHMMSS parts(x);
    const auto h = parts.hours().count();
    const auto m = parts.minutes().count();
    const auto s = parts.seconds().count();
    
    NSDateComponents* comp = [NSDateComponents new];
    [comp setYear:2022];
    [comp setMonth:1];
    [comp setDay:1];
    [comp setHour:h];
    [comp setMinute:m];
    [comp setSecond:s];
    NSDate* date = [_DateFormatterStateGet().cal dateFromComponents:comp];
    
//    if (full) return [[_DateFormatterStateGet().timeFormatterHHMMSS stringFromDate:date] UTF8String];
    
    if (_DateFormatterStateGet().showsAMPM && !s && !m) {
        return [[_DateFormatterStateGet().timeFormatterHH stringFromDate:date] UTF8String];
    } else if (!s) {
        return [[_DateFormatterStateGet().timeFormatterHHMM stringFromDate:date] UTF8String];
    } else {
        return [[_DateFormatterStateGet().timeFormatterHHMMSS stringFromDate:date] UTF8String];
    }
}

// 3:46:29 PM / 15:46:29 -> 56789
inline TimeOfDay TimeOfDayFromString(std::string x, bool assumeAM=true) {
    // Convert input to lowercase / remove all spaces
    const char timeSeparator = _DateFormatterStateGet().timeSeparator;
    bool hasSeparators = false;
    for (auto it=x.begin(); it!=x.end();) {
        *it = std::tolower(*it);
        hasSeparators |= (timeSeparator && *it==timeSeparator);
        if (std::isspace(*it))  it = x.erase(it);
        else                    it++;
    }
    
    // Insert time separators (112233 -> 11:22:33) if they're missing, so we don't reject the input if they are missing
    if (timeSeparator && !hasSeparators && !x.empty()) {
        bool started = false;
        size_t count = 0;
        for (auto it=x.end()-1; it!=x.begin(); it--) {
            started |= std::isdigit(*it);
            if (count == 1) x.insert(it, timeSeparator);
            count += started;
            if (count == 2) count = 0;
        }
    }
    
    // Add AM/PM if it isn't specified, so we don't reject the input if it's just missing am/pm
    if (_DateFormatterStateGet().showsAMPM &&
        !Toastbox::String::EndsWith("am", x) &&
        !Toastbox::String::EndsWith("pm", x)) {
        x += (assumeAM ? "am" : "pm");
    }
    
    NSDate* date = [_DateFormatterStateGet().timeFormatterHHMMSS dateFromString:@(x.c_str())];
    if (!date) date = [_DateFormatterStateGet().timeFormatterHHMM dateFromString:@(x.c_str())];
    if (!date) date = [_DateFormatterStateGet().timeFormatterHH dateFromString:@(x.c_str())];
    if (!date) throw Toastbox::RuntimeError("invalid time of day: %s", x.c_str());
    
    NSDateComponents* comp = [_DateFormatterStateGet().cal
        components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:date];
    
    const TimeOfDay t([comp hour]*60*60 + [comp minute]*60 + [comp second]);
    TimeOfDayValidate(t);
    return t;
}

inline std::optional<DayOfYear> DayOfYearFromString(std::string_view x) {
    NSDate* date = [_DateFormatterStateGet().dayOfYearFormatter dateFromString:@(std::string(x).c_str())];
    if (!date) return std::nullopt;
    
    NSDateComponents* comp = [_DateFormatterStateGet().cal
        components:NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
    if (!comp) return std::nullopt;
    
    const DayOfYear r = DayOfYear{ {(uint8_t)[comp month]}, {(uint8_t)[comp day]} };
    try {
        DayOfYearValidate(r);
    } catch (...) { return std::nullopt; }
    
    return r;
}

inline std::string StringFromDayOfYear(DayOfYear x) {
    NSDateComponents* comp = [NSDateComponents new];
    [comp setMonth:x.month.x];
    [comp setDay:x.day.x];
    NSDate* date = [_DateFormatterStateGet().cal dateFromComponents:comp];
    return [[_DateFormatterStateGet().dayOfYearFormatter stringFromDate:date] UTF8String];
}

inline std::string DayOfYearPlaceholderString() {
    static std::string X = StringFromDayOfYear(DayOfYear{
        .month = 10,
        .day = 31,
    });
    return X;
}

} // namespace Calendar

using Ms = std::chrono::duration<uint32_t, std::milli>;

struct [[gnu::packed]] DayCount {
    uint32_t x;
};

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
        DayCount DayInterval;
    };
};

enum class LEDs : uint8_t {
    None  = 0,
    Green = 1<<0,
    Red   = 1<<1,
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

//inline float _MsForDuration(const Duration& x) {
//    switch (x.unit) {
//    case Duration::Unit::Seconds: return x.value                * 1000;
//    case Duration::Unit::Minutes: return x.value           * 60 * 1000;
//    case Duration::Unit::Hours:   return x.value      * 60 * 60 * 1000;
//    case Duration::Unit::Days:    return x.value * 24 * 60 * 60 * 1000;
//    default:                      abort();
//    }
//}

inline Ms MsForDuration(const Duration& x) {
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
    LEDs flashLEDs;
};

struct [[gnu::packed]] CaptureTrigger {
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

struct [[gnu::packed]] CaptureTriggers {
    CaptureTrigger triggers[32] = {};
    uint8_t count = 0;
};

struct [[gnu::packed]] CaptureTriggersSerialized {
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
static_assert(sizeof(CaptureTriggersSerialized) == CaptureTriggersSerialized::Size);

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
inline void Serialize(T& data, const CaptureTriggers& x) {
    static_assert(sizeof(data) == sizeof(CaptureTriggersSerialized));
    
    CaptureTriggersSerialized s = {
        .version = CaptureTriggersSerialized::Version,
    };
    
    // CaptureTriggers -> CaptureTriggersSerialized
    {
        auto d = _Compress((uint8_t*)&x, (uint8_t*)&x+sizeof(x));
        if (d.size() > sizeof(s.payload)) {
            throw Toastbox::RuntimeError("data doesn't fit in CaptureTriggersSerialized (length: %ju, capacity: %ju)",
                (uintmax_t)d.size(), (uintmax_t)sizeof(s.payload));
        }
        memcpy(s.payload, d.data(), d.size());
    }
    
    // CaptureTriggersSerialized -> data
    {
        memcpy(&data, &s, sizeof(s));
    }
}

template<typename T>
inline void Deserialize(CaptureTriggers& x, const T& data) {
    static_assert(sizeof(data) == sizeof(CaptureTriggersSerialized));
    
    CaptureTriggersSerialized s;
    
    // data -> CaptureTriggersSerialized
    {
        memcpy(&s, &data, sizeof(data));
        
        if (s.version != CaptureTriggersSerialized::Version) {
            throw Toastbox::RuntimeError("CaptureTriggersSerialized version invalid (expected: %ju, got: %ju)",
                (uintmax_t)CaptureTriggersSerialized::Version, (uintmax_t)s.version);
        }
    }
    
    // CaptureTriggersSerialized -> CaptureTriggers
    {
        auto d = _Decompress(s.payload, s.payload+sizeof(s.payload));
        if (d.size() != sizeof(x)) {
            throw Toastbox::RuntimeError("deserialized data length doesn't match sizeof(CaptureTriggers) (expected: %ju, got: %ju)",
                (uintmax_t)sizeof(x), (uintmax_t)d.size());
        }
        memcpy(&x, d.data(), d.size());
        if (x.count > std::size(x.triggers)) {
            throw Toastbox::RuntimeError("invalid deserialized trigger count (got: %ju, max: %ju)",
                (uintmax_t)x.count, (uintmax_t)std::size(x.triggers));
        }
    }
}


//inline CaptureTriggersSerialized Serialize(const CaptureTriggers& x) {
//    CaptureTriggersSerialized y = {
//        .version = CaptureTriggersSerialized::Version,
//    };
//    
//    auto d = _Compress((uint8_t*)&x, (uint8_t*)&x+sizeof(x));
//    if (d.size() > sizeof(y.payload)) {
//        throw Toastbox::RuntimeError("data doesn't fit in CaptureTriggersSerialized (length: %ju, capacity: %ju)",
//            (uintmax_t)d.size(), (uintmax_t)sizeof(y.payload));
//    }
//    memcpy(y.payload, d.data(), d.size());
//    return y;
//}
//
//inline CaptureTriggers Deserialize(const CaptureTriggersSerialized& x) {
//    if (x.version != CaptureTriggersSerialized::Version) {
//        throw Toastbox::RuntimeError("CaptureTriggersSerialized version invalid (expected: %ju, got: %ju)",
//            (uintmax_t)CaptureTriggersSerialized::Version, (uintmax_t)x.version);
//    }
//    
//    CaptureTriggers y;
//    auto d = _Decompress(x.payload, x.payload+sizeof(x.payload));
//    if (d.size() != sizeof(y)) {
//        throw Toastbox::RuntimeError("deserialized data length doesn't match sizeof(CaptureTriggers) (expected: %ju, got: %ju)",
//            (uintmax_t)sizeof(y), (uintmax_t)d.size());
//    }
//    memcpy(&y, d.data(), d.size());
//    if (y.count > std::size(y.triggers)) {
//        throw Toastbox::RuntimeError("invalid deserialized trigger count (got: %ju, max: %ju)",
//            (uintmax_t)y.count, (uintmax_t)std::size(y.triggers));
//    }
//    return y;
//}





} // namespace DeviceSettings
