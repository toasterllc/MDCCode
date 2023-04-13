#pragma once
#include <vector>

namespace DeviceSettings {

namespace Calendar {

// TimeOfDay: a particular time of an unspecified day, in seconds [0,86400]
struct [[gnu::packed]] TimeOfDay { uint32_t x; };

// DayOfWeek: a particular day of an unspecified week
struct [[gnu::packed]] DayOfWeek { uint8_t x; };
enum DayOfWeek_ { Mon, Tue, Wed, Thu, Fri, Sat, Sun };

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






inline void TimeOfDayValidate(const TimeOfDay& x) {
    if (x.x > 24*60*60) throw Toastbox::RuntimeError("invalid TimeOfDay: %ju", (uintmax_t)x.x);
}

inline void DayOfWeekValidate(const DayOfWeek& x) {
    if (x.x >= 7) throw Toastbox::RuntimeError("invalid DayOfWeek: %ju", (uintmax_t)x.x);
}

inline void DayOfMonthValidate(const DayOfMonth& x) {
    if (x.x<1 || x.x>31) throw Toastbox::RuntimeError("invalid DayOfMonth: %ju", (uintmax_t)x.x);
}

inline void MonthOfYearValidate(const MonthOfYear& x) {
    if (x.x<1 || x.x>12) throw Toastbox::RuntimeError("invalid MonthOfYear: %ju", (uintmax_t)x.x);
}

inline void DayOfYearValidate(const DayOfYear& x) {
    MonthOfYearValidate(x.month);
    DayOfMonthValidate(x.day);
}





inline std::string StringForDayOfWeek(const DayOfWeek& x) {
    switch (x.x) {
    case DayOfWeek_::Mon: return "Mon";
    case DayOfWeek_::Tue: return "Tue";
    case DayOfWeek_::Wed: return "Wed";
    case DayOfWeek_::Thu: return "Thu";
    case DayOfWeek_::Fri: return "Fri";
    case DayOfWeek_::Sat: return "Sat";
    case DayOfWeek_::Sun: return "Sun";
    }
    abort();
}

inline constexpr uint8_t DaysOfWeekMask(DayOfWeek day) {
    return 1 << day.x;
}

inline bool DaysOfWeekGet(const DaysOfWeek& x, DayOfWeek day) {
    return x.x & DaysOfWeekMask(day);
}

inline void DaysOfWeekSet(DaysOfWeek& x, DayOfWeek day, bool y) {
    x.x &= ~DaysOfWeekMask(day);
    if (y) x.x |= DaysOfWeekMask(day);
}

inline std::vector<DayOfWeek> VectorFromDaysOfWeek(const DaysOfWeek& x) {
    std::vector<DayOfWeek> r;
    for (DayOfWeek i={0}; i.x<7; i.x++) {
        if (x.x & DaysOfWeekMask(i)) {
            r.push_back(i);
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

inline std::string StringFromDayOfMonth(const DayOfMonth& x) {
    return std::to_string(x.x);
}

inline constexpr uint32_t DaysOfMonthMask(DayOfMonth day) {
    return 1 << (day.x-1);
}

inline bool DaysOfMonthGet(const DaysOfMonth& x, DayOfMonth day) {
    return x.x & DaysOfMonthMask(day);
}

inline void DaysOfMonthSet(DaysOfMonth& x, DayOfMonth day, bool y) {
    x.x &= ~DaysOfMonthMask(day);
    if (y) x.x |= DaysOfMonthMask(day);
}

inline std::vector<DayOfMonth> VectorFromDaysOfMonth(const DaysOfMonth& x) {
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








struct _TimeFormatState {
    NSCalendar* calendar = nil;
    NSDateFormatter* dateFormatterHH = nil;
    NSDateFormatter* dateFormatterHHMM = nil;
    NSDateFormatter* dateFormatterHHMMSS = nil;
    bool showsAMPM = false;
    char timeSeparator = 0;
};

static _TimeFormatState _TimeFormatStateCreate() {
    _TimeFormatState x;
    x.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    {
        x.dateFormatterHH = [[NSDateFormatter alloc] init];
        [x.dateFormatterHH setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.dateFormatterHH setCalendar:x.calendar];
        [x.dateFormatterHH setTimeZone:[x.calendar timeZone]];
        [x.dateFormatterHH setLocalizedDateFormatFromTemplate:@"hh"];
        [x.dateFormatterHH setLenient:true];
    }
    
    {
        x.dateFormatterHHMM = [[NSDateFormatter alloc] init];
        [x.dateFormatterHHMM setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.dateFormatterHHMM setCalendar:x.calendar];
        [x.dateFormatterHHMM setTimeZone:[x.calendar timeZone]];
        [x.dateFormatterHHMM setLocalizedDateFormatFromTemplate:@"hhmm"];
        [x.dateFormatterHHMM setLenient:true];
    }
    
    {
        x.dateFormatterHHMMSS = [[NSDateFormatter alloc] init];
        [x.dateFormatterHHMMSS setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.dateFormatterHHMMSS setCalendar:x.calendar];
        [x.dateFormatterHHMMSS setTimeZone:[x.calendar timeZone]];
        [x.dateFormatterHHMMSS setLocalizedDateFormatFromTemplate:@"hhmmss"];
        [x.dateFormatterHHMMSS setLenient:true];
    }
    
    NSString* dateFormat = [x.dateFormatterHHMMSS dateFormat];
    x.showsAMPM = [dateFormat containsString:@"a"];
    x.timeSeparator = ([dateFormat containsString:@":"] ? ':' : 0);
    
    return x;
}

static _TimeFormatState& _TimeFormatStateGet() {
    static _TimeFormatState x = _TimeFormatStateCreate();
    return x;
}

// 56789 -> 3:46:29 PM / 15:46:29 (depending on locale)
inline std::string StringFromTimeOfDay(TimeOfDay x) {
    const uint32_t h = x.x/(60*60);
    x.x -= h*60*60;
    const uint32_t m = x.x/60;
    x.x -= m*60;
    const uint32_t s = x.x;
    
    NSDateComponents* comp = [NSDateComponents new];
    [comp setYear:2022];
    [comp setMonth:1];
    [comp setDay:1];
    [comp setHour:h];
    [comp setMinute:m];
    [comp setSecond:s];
    NSDate* date = [_TimeFormatStateGet().calendar dateFromComponents:comp];
    
//    if (full) return [[_TimeFormatStateGet().dateFormatterHHMMSS stringFromDate:date] UTF8String];
    
    if (_TimeFormatStateGet().showsAMPM && !s && !m) {
        return [[_TimeFormatStateGet().dateFormatterHH stringFromDate:date] UTF8String];
    } else if (!s) {
        return [[_TimeFormatStateGet().dateFormatterHHMM stringFromDate:date] UTF8String];
    } else {
        return [[_TimeFormatStateGet().dateFormatterHHMMSS stringFromDate:date] UTF8String];
    }
}

// 3:46:29 PM / 15:46:29 -> 56789
inline TimeOfDay TimeOfDayFromString(std::string x, bool assumeAM=true) {
    // Convert input to lowercase / remove all spaces
    const char timeSeparator = _TimeFormatStateGet().timeSeparator;
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
    if (_TimeFormatStateGet().showsAMPM &&
        !Toastbox::String::EndsWith("am", x) &&
        !Toastbox::String::EndsWith("pm", x)) {
        x += (assumeAM ? "am" : "pm");
    }
    
    NSDate* date = [_TimeFormatStateGet().dateFormatterHHMMSS dateFromString:@(x.c_str())];
    if (!date) date = [_TimeFormatStateGet().dateFormatterHHMM dateFromString:@(x.c_str())];
    if (!date) date = [_TimeFormatStateGet().dateFormatterHH dateFromString:@(x.c_str())];
    if (!date) throw Toastbox::RuntimeError("invalid time of day: %s", x.c_str());
    
    NSDateComponents* comp = [_TimeFormatStateGet().calendar
        components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:date];
    
    const TimeOfDay t = { (uint32_t)([comp hour]*60*60 + [comp minute]*60 + [comp second]) };
    TimeOfDayValidate(t);
    return t;
}




struct _DayOfYearState {
    NSCalendar* cal = nil;
    NSDateFormatter* fmt = nil;
};

inline _DayOfYearState _DayOfYearStateCreate() {
    _DayOfYearState x;
    x.cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    x.fmt = [[NSDateFormatter alloc] init];
    [x.fmt setLocale:[NSLocale autoupdatingCurrentLocale]];
    [x.fmt setCalendar:x.cal];
    [x.fmt setTimeZone:[x.cal timeZone]];
    [x.fmt setLocalizedDateFormatFromTemplate:@"MMMd"];
    [x.fmt setLenient:true];
    
    return x;
}

inline _DayOfYearState& _DayOfYearStateGet() {
    static _DayOfYearState x = _DayOfYearStateCreate();
    return x;
}







//inline NSDateFormatter* _DayOfYearDateFormatterCreate() {
//    NSDateFormatter* x = [[NSDateFormatter alloc] init];
//    [x setLocale:[NSLocale autoupdatingCurrentLocale]];
//    [x setLocalizedDateFormatFromTemplate:@"Md"];
//    [x setLenient:true];
//    return x;
//}
//
//inline NSDateFormatter* _DayOfYearDateFormatter() {
//    static NSDateFormatter* X = _DayOfYearDateFormatterCreate();
//    return X;
//}

inline std::optional<DayOfYear> DayOfYearFromString(std::string_view x) {
    NSDate* date = [_DayOfYearStateGet().fmt dateFromString:@(std::string(x).c_str())];
    if (!date) return std::nullopt;
    
    NSDateComponents* comp = [_DayOfYearStateGet().cal
        components:NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
    if (!comp) return std::nullopt;
    
    const DayOfYear r = DayOfYear{ {(uint8_t)[comp month]}, {(uint8_t)[comp day]} };
    try {
        DayOfYearValidate(r);
    } catch (...) { return std::nullopt; }
    
    return r;
}

inline std::string StringFromDayOfYear(const DayOfYear& x) {
    NSDateComponents* comp = [NSDateComponents new];
    [comp setMonth:x.month.x];
    [comp setDay:x.day.x];
    NSDate* date = [_DayOfYearStateGet().cal dateFromComponents:comp];
    return [[_DayOfYearStateGet().fmt stringFromDate:date] UTF8String];
}

inline std::string DayOfYearPlaceholderString() {
    static std::string X = StringFromDayOfYear(DayOfYear{
        .month = 10,
        .day = 31,
    });
    return X;
}

} // namespace Calendar



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

inline float _MsForDuration(const Duration& x) {
    switch (x.unit) {
    case Duration::Unit::Seconds: return x.value                * 1000;
    case Duration::Unit::Minutes: return x.value           * 60 * 1000;
    case Duration::Unit::Hours:   return x.value      * 60 * 60 * 1000;
    case Duration::Unit::Days:    return x.value * 24 * 60 * 60 * 1000;
    default:                      abort();
    }
}

inline uint32_t MsForDuration(const Duration& x) {
    return std::clamp(_MsForDuration(x), 0.f, (float)UINT32_MAX);
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
