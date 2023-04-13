#pragma once
#include <vector>
#include <chrono>
#include "date/date.h"
#include "Toastbox/RuntimeError.h"
#include "Toastbox/NumForStr.h"
#include "Toastbox/String.h"

namespace MDCStudio {
namespace Calendar {

// TimeOfDay: a particular time of an unspecified day, in seconds [0,86400]
using TimeOfDay = std::chrono::duration<uint32_t>;
// TimeOfDayHHMMSS: the extracted hour/minute/second components of a TimeOfDay
using TimeOfDayHHMMSS = date::hh_mm_ss<TimeOfDay>;
// DayOfWeek: a particular day of an unspecified week
using DayOfWeek = date::weekday;
// DayOfMonth: a particular day of an unspecified month [1,31]
using DayOfMonth = date::day;
// MonthOfYear: a particular month of an unspecified year [1,12]
using MonthOfYear = date::month;
// DayOfYear: a particular day of an unspecified year
using DayOfYear = date::month_day;

// DaysOfWeek: a set of days of an unspecified week
struct [[gnu::packed]] DaysOfWeek { uint8_t x; };
// DaysOfMonth: a set of days of an unspecified month
struct [[gnu::packed]] DaysOfMonth { uint32_t x; };
// DaysOfYear: a set of days of an unspecified year
struct [[gnu::packed]] DaysOfYear { DaysOfMonth x[12]; };

inline void TimeOfDayValidate(TimeOfDay x) {
    if (x.count() > 24*60*60) throw Toastbox::RuntimeError("invalid TimeOfDay: %ju", (uintmax_t)x.count());
}

inline void DayOfWeekValidate(DayOfWeek x) {
    if (!x.ok()) throw Toastbox::RuntimeError("invalid DayOfWeek: %ju", (uintmax_t)x.c_encoding());
}

inline void DayOfMonthValidate(DayOfMonth x) {
    if (!x.ok()) throw Toastbox::RuntimeError("invalid DayOfMonth: %ju", (uintmax_t)(unsigned)(x));
}

inline void MonthOfYearValidate(MonthOfYear x) {
    if (!x.ok()) throw Toastbox::RuntimeError("invalid MonthOfYear: %ju", (uintmax_t)(unsigned)(x));
}

inline void DayOfYearValidate(DayOfYear x) {
    if (!x.ok()) throw Toastbox::RuntimeError("invalid DayOfYear: %ju/%ju",
        (uintmax_t)(unsigned)(x.month()), (uintmax_t)(unsigned)(x.day()));
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
    try {
        DayOfMonth y(Toastbox::IntForStr<unsigned>(x));
        DayOfMonthValidate(y);
        return y;
    } catch (...) { return std::nullopt; }
}

inline std::string StringFromDayOfMonth(DayOfMonth x) {
    return std::to_string((unsigned)x);
}

inline constexpr uint32_t DaysOfMonthMask(DayOfMonth day) {
    return 1 << ((unsigned)day-1);
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
    for (uint8_t i=1; i<=31; i++) {
        const DayOfMonth d(i);
        if (DaysOfMonthGet(x, d)) {
            r.push_back(d);
        }
    }
    return r;
}

inline DaysOfMonth DaysOfMonthFromVector(const std::vector<DayOfMonth>& x) {
    DaysOfMonth r = {};
    for (DayOfMonth d : x) {
        DayOfMonthValidate(d);
        DaysOfMonthSet(r, d, true);
    }
    return r;
}






inline std::vector<DayOfYear> VectorFromDaysOfYear(const DaysOfYear& x) {
    std::vector<DayOfYear> r;
    for (uint8_t i=1; i<=12; i++) {
        const std::vector<DayOfMonth> days = VectorFromDaysOfMonth(x.x[i-1]);
        for (const DayOfMonth& d : days) {
            r.push_back(DayOfYear{MonthOfYear(i), d});
        }
    }
    return r;
}

inline DaysOfYear DaysOfYearFromVector(const std::vector<DayOfYear>& x) {
    DaysOfYear r = {};
    for (const DayOfYear& d : x) {
        DayOfYearValidate(d);
        DaysOfMonthSet(r.x[(unsigned)d.month()-1], d.day(), true);
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
    const TimeOfDayHHMMSS parts(x);
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
    
    const DayOfYear r = DayOfYear{ MonthOfYear((int)[comp month]), DayOfMonth((int)[comp day]) };
    try {
        DayOfYearValidate(r);
    } catch (...) { return std::nullopt; }
    
    return r;
}

inline std::string StringFromDayOfYear(DayOfYear x) {
    NSDateComponents* comp = [NSDateComponents new];
    [comp setMonth:(unsigned)x.month()];
    [comp setDay:(unsigned)x.day()];
    NSDate* date = [_DateFormatterStateGet().cal dateFromComponents:comp];
    return [[_DateFormatterStateGet().dayOfYearFormatter stringFromDate:date] UTF8String];
}

inline std::string DayOfYearPlaceholderString() {
    static std::string X = StringFromDayOfYear(DayOfYear(MonthOfYear(10), DayOfMonth(31)));
    return X;
}

} // namespace Calendar
} // namespace MDCStudio
