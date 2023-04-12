#pragma once
#include <vector>

namespace DeviceSettings {

namespace Calendar {

using Day = uint8_t;
using Month = uint8_t;

// WeekDay: a particular day of an unspecified week
using WeekDay = uint8_t;
enum WeekDay_ {
    Mon,
    Tue,
    Wed,
    Thu,
    Fri,
    Sat,
    Sun,
};

// MonthDay: a particular day of an unspecified month
struct [[gnu::packed]] MonthDay {
    Day day;
};

// YearDay: a particular day of an unspecified year
struct [[gnu::packed]] YearDay {
    Month month;
    Day day;
};

// WeekDays: a set of days of an unspecified week
struct [[gnu::packed]] WeekDays {
    uint8_t x;
};

// MonthDays: a set of days of an unspecified month
struct [[gnu::packed]] MonthDays {
    uint32_t x;
};

// YearDays: a set of days of an unspecified year
struct [[gnu::packed]] YearDays {
    MonthDays x[12];
};








inline void DayValidate(const Day& x) {
    if (x<1 || x>31) throw Toastbox::RuntimeError("invalid Day: %ju", (uintmax_t)x);
}

inline void MonthValidate(const Month& x) {
    if (x<1 || x>12) throw Toastbox::RuntimeError("invalid Month: %ju", (uintmax_t)x);
}

inline void WeekDayValidate(const WeekDay& x) {
    using X = WeekDay_;
    switch (x) {
    case X::Mon:  break;
    case X::Tue:  break;
    case X::Wed:  break;
    case X::Thu:  break;
    case X::Fri:  break;
    case X::Sat:  break;
    case X::Sun:  break;
    default: throw Toastbox::RuntimeError("invalid WeekDay: %ju", (uintmax_t)x);
    }
}

inline void MonthDayValidate(const MonthDay& x) {
    DayValidate(x.day);
}

inline void YearDayValidate(const YearDay& x) {
    DayValidate(x.day);
    MonthValidate(x.month);
}





inline std::string StringForWeekDay(const WeekDay& x) {
    switch (x) {
    case WeekDay_::Mon: return "Mon";
    case WeekDay_::Tue: return "Tue";
    case WeekDay_::Wed: return "Wed";
    case WeekDay_::Thu: return "Thu";
    case WeekDay_::Fri: return "Fri";
    case WeekDay_::Sat: return "Sat";
    case WeekDay_::Sun: return "Sun";
    }
    abort();
}

inline constexpr uint8_t WeekDaysMask(WeekDay day) {
    return 1 << day;
}

inline bool WeekDaysGet(const WeekDays& x, WeekDay day) {
    return x.x & WeekDaysMask(day);
}

inline void WeekDaysSet(WeekDays& x, WeekDay day, bool y) {
    x.x &= ~WeekDaysMask(day);
    if (y) x.x |= WeekDaysMask(day);
}

inline std::vector<WeekDay> VectorFromWeekDays(const WeekDays& x) {
    std::vector<WeekDay> r;
    for (WeekDay i=0; i<7; i++) {
        if (x.x & WeekDaysMask(i)) {
            r.push_back(i);
        }
    }
    return r;
}

inline WeekDays WeekDaysFromVector(const std::vector<WeekDay>& x) {
    WeekDays r = {};
    for (const WeekDay& d : x) {
        WeekDayValidate(d);
        WeekDaysSet(r, d, true);
    }
    return r;
}







inline std::optional<MonthDay> MonthDayFromString(std::string_view x) {
    Day day = 0;
    try {
        Toastbox::IntForStr(day, x);
        DayValidate(day);
    } catch (...) { return std::nullopt; }
    return MonthDay{ .day = day };
}

inline std::string StringFromMonthDay(const MonthDay& x) {
    return std::to_string(x.day);
}

inline constexpr uint32_t MonthDaysMask(Day day) {
    return 1 << (day-1);
}

inline bool MonthDaysGet(const MonthDays& x, Day day) {
    return x.x & MonthDaysMask(day);
}

inline void MonthDaysSet(MonthDays& x, Day day, bool y) {
    x.x &= ~MonthDaysMask(day);
    if (y) x.x |= MonthDaysMask(day);
}

inline std::vector<MonthDay> VectorFromMonthDays(const MonthDays& x) {
    std::vector<MonthDay> r;
    for (Day day=1; day<=31; day++) {
        if (MonthDaysGet(x, day)) {
            r.push_back(MonthDay{
                .day = day,
            });
        }
    }
    return r;
}

inline MonthDays MonthDaysFromVector(const std::vector<MonthDay>& x) {
    MonthDays r = {};
    for (MonthDay day : x) {
        MonthDayValidate(day);
        MonthDaysSet(r, day.day, true);
    }
    return r;
}






inline std::vector<YearDay> VectorFromYearDays(const YearDays& x) {
    std::vector<YearDay> r;
    for (Month m=1; m<=12; m++) {
        const std::vector<MonthDay> monthDays = VectorFromMonthDays(x.x[m-1]);
        for (const MonthDay& d : monthDays) {
            r.push_back(YearDay{
                .month = m,
                .day = d.day,
            });
        }
    }
    return r;
}

inline YearDays YearDaysFromVector(const std::vector<YearDay>& x) {
    YearDays r = {};
    for (const YearDay& d : x) {
        YearDayValidate(d);
        MonthDaysSet(r.x[d.month-1], d.day, true);
    }
    return r;
}






struct _YearDayState {
    NSCalendar* cal = nil;
    NSDateFormatter* fmt = nil;
};

inline _YearDayState _YearDayStateCreate() {
    _YearDayState x;
    x.cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    x.fmt = [[NSDateFormatter alloc] init];
    [x.fmt setLocale:[NSLocale autoupdatingCurrentLocale]];
    [x.fmt setCalendar:x.cal];
    [x.fmt setTimeZone:[x.cal timeZone]];
    [x.fmt setLocalizedDateFormatFromTemplate:@"MMMd"];
    [x.fmt setLenient:true];
    
    return x;
}

inline _YearDayState& _YearDayStateGet() {
    static _YearDayState x = _YearDayStateCreate();
    return x;
}







//inline NSDateFormatter* _YearDayDateFormatterCreate() {
//    NSDateFormatter* x = [[NSDateFormatter alloc] init];
//    [x setLocale:[NSLocale autoupdatingCurrentLocale]];
//    [x setLocalizedDateFormatFromTemplate:@"Md"];
//    [x setLenient:true];
//    return x;
//}
//
//inline NSDateFormatter* _YearDayDateFormatter() {
//    static NSDateFormatter* X = _YearDayDateFormatterCreate();
//    return X;
//}

inline std::optional<YearDay> YearDayFromString(std::string_view x) {
    NSDate* date = [_YearDayStateGet().fmt dateFromString:@(std::string(x).c_str())];
    if (!date) return std::nullopt;
    
    NSDateComponents* comp = [_YearDayStateGet().cal
        components:NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
    if (!comp) return std::nullopt;
    
    YearDay r = YearDay{
        .month = (Month)[comp month],
        .day = (Day)[comp day],
    };
    
    try {
        YearDayValidate(r);
    } catch (...) { return std::nullopt; }
    
    return r;
}

inline std::string StringFromYearDay(const YearDay& x) {
    NSDateComponents* comp = [NSDateComponents new];
    [comp setMonth:x.month];
    [comp setDay:x.day];
    NSDate* date = [_YearDayStateGet().cal dateFromComponents:comp];
    return [[_YearDayStateGet().fmt stringFromDate:date] UTF8String];
}

inline std::string YearDayPlaceholderString() {
    static std::string X = StringFromYearDay(YearDay{
        .month = 10,
        .day = 31,
    });
    return X;
}









} // namespace Calendar









struct [[gnu::packed]] CaptureTrigger {
    enum class Type : uint8_t {
        Time,
        Motion,
        Button,
    };
    
    struct [[gnu::packed]] DayInterval {
        uint32_t interval;
    };
    
    struct [[gnu::packed]] Repeat {
        enum class Type : uint8_t {
            Daily,
            WeekDays,
            YearDays,
            DayInterval,
        };
        
        Type type;
        union {
            Calendar::WeekDays weekDays;
            Calendar::YearDays yearDays;
            DayInterval dayInterval;
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
    
    struct [[gnu::packed]] Capture {
        uint32_t count;
        Duration interval;
        LEDs flashLEDs;
    };
    
    Type type = Type::Time;
    
    union {
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                uint32_t time;
                Repeat repeat;
            } schedule;
            
            Capture capture;
        } time;
        
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t start;
                    uint32_t end;
                } timeRange;
                
                Repeat repeat;
            } schedule;
            
            Capture capture;
            
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    Duration duration;
                } ignoreTriggerDuration;
                
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t count;
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
