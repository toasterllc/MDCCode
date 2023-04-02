#pragma once

namespace DeviceSettings {
namespace Calendar {

enum class WeekDays : uint8_t {
    None = 0,
    Mon  = 1<<0,
    Tue  = 1<<1,
    Wed  = 1<<2,
    Thu  = 1<<3,
    Fri  = 1<<4,
    Sat  = 1<<5,
    Sun  = 1<<6,
};

using Day = uint8_t;
using Month = uint8_t;

// MonthDay: a particular day of an unspecified month
struct [[gnu::packed]] MonthDay {
    Day day;
};

// YearDay: a particular day of an unspecified year
struct [[gnu::packed]] YearDay {
    Month month;
    Day day;
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

inline void MonthDayValidate(const MonthDay& x) {
    DayValidate(x.day);
}

inline void YearDayValidate(const YearDay& x) {
    DayValidate(x.day);
    MonthValidate(x.month);
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









} // namespace Calendar
} // namespace DeviceSettings
