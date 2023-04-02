#import "CaptureTriggersView.h"
#import <vector>
#import <optional>
#import "Toastbox/Mac/Util.h"
#import "Toastbox/RuntimeError.h"
#import "Toastbox/IntForStr.h"
#import "DeviceSettings.h"
#import "Toastbox/Defer.h"
using namespace DeviceSettings;

#warning TODO: add version, or is the version specified by whatever contains Trigger instances?

struct [[gnu::packed]] Trigger {
    enum class Type : uint8_t {
        Time,
        Motion,
        Button,
    };
    
    enum class Cadence : uint8_t {
        Daily,
        Weekly,
        Monthly,
        Yearly,
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
        
        uint32_t value;
        Unit unit;
    };
    
    Type type = Type::Time;
    
    union {
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                uint32_t time;
                Cadence cadence;
                union {
                    Calendar::WeekDays weekDays;
                    Calendar::MonthDays monthDays;
                    Calendar::YearDays yearDays;
                };
            } schedule;
            
            struct [[gnu::packed]] {
                uint32_t count;
                Duration interval;
                LEDs flashLEDs;
            } capture;
            
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t count;
                } maxTotalTriggerCount;
            } constraints;
        } time;
        
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t start;
                    uint32_t end;
                } timeLimit;
                
                struct [[gnu::packed]] {
                    bool enable;
                    Cadence cadence;
                    union {
                        Calendar::WeekDays weekDays;
                        Calendar::MonthDays monthDays;
                        Calendar::YearDays yearDays;
                    };
                } dayLimit;
            } schedule;
            
            struct [[gnu::packed]] {
                uint32_t count;
                Duration interval;
                LEDs flashLEDs;
            } capture;
            
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    Duration duration;
                } ignoreTriggerDuration;
                
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t count;
                } maxTriggerCount;
                
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t count;
                } maxTotalTriggerCount;
            } constraints;
        } motionButton;
    };
};

constexpr uint32_t _TimeStartInit = 32400; // 9 AM
constexpr uint32_t _TimeEndInit = 61200;   // 5 PM
constexpr Calendar::WeekDays _WeekDaysInit = (Calendar::WeekDays)(
    std::to_underlying(Calendar::WeekDays::Mon) |
    std::to_underlying(Calendar::WeekDays::Tue) |
    std::to_underlying(Calendar::WeekDays::Wed) |
    std::to_underlying(Calendar::WeekDays::Thu) |
    std::to_underlying(Calendar::WeekDays::Fri)
);

static const Calendar::MonthDays _MonthDaysInit = Calendar::MonthDaysFromVector({Calendar::MonthDay{14}, Calendar::MonthDay{28}});
static const Calendar::YearDays _YearDaysInit = Calendar::YearDaysFromVector({Calendar::YearDay{9,20}, Calendar::YearDay{12,31}});

static void _InitTriggerScheduleCadence(Trigger& t) {
    switch (t.type) {
    case Trigger::Type::Time: {
        auto& x = t.time.schedule;
        switch (x.cadence) {
        case Trigger::Cadence::Daily:
            break;
        case Trigger::Cadence::Weekly:
            x.weekDays = _WeekDaysInit;
            break;
        case Trigger::Cadence::Monthly:
            x.monthDays = _MonthDaysInit;
            break;
        case Trigger::Cadence::Yearly:
            x.yearDays = _YearDaysInit;
            break;
        default:
            abort();
        }
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = t.motionButton.schedule.dayLimit;
        switch (x.cadence) {
        case Trigger::Cadence::Daily:
            break;
        case Trigger::Cadence::Weekly:
            x.weekDays = _WeekDaysInit;
            break;
        case Trigger::Cadence::Monthly:
            x.monthDays = _MonthDaysInit;
            break;
        case Trigger::Cadence::Yearly:
            x.yearDays = _YearDaysInit;
            break;
        default:
            abort();
        }
        break;
    }
    
    default:
        abort();
    }
}

static void _InitTrigger(Trigger& t, Trigger::Type type) {
    t.type = type;
    switch (t.type) {
    case Trigger::Type::Time: {
        auto& x = t.time;
        
        x.schedule = {
            .time = _TimeStartInit,
            .cadence = Trigger::Cadence::Daily,
        };
        
        x.capture = {
            .count = 3,
            .interval = Trigger::Duration{
                .value = 1,
                .unit = Trigger::Duration::Unit::Seconds,
            },
            .flashLEDs = Trigger::LEDs::None,
        };
        
        x.constraints = {
            .maxTotalTriggerCount = {
                .enable = false,
                .count = 1,
            }
        };
        
        break;
    }
    
    case Trigger::Type::Motion: {
        auto& x = t.motionButton;
        
        x.schedule = {
            .timeLimit = {
                .enable = true,
                .start = _TimeStartInit,
                .end = _TimeEndInit,
            },
            .dayLimit = {
                .enable = true,
                .cadence = Trigger::Cadence::Weekly,
                .weekDays = _WeekDaysInit,
            },
        };
        
        x.capture = {
            .count = 3,
            .interval = Trigger::Duration{
                .value = 1,
                .unit = Trigger::Duration::Unit::Seconds,
            },
            .flashLEDs = Trigger::LEDs::None,
        };
        
        x.constraints = {
            .ignoreTriggerDuration = {
                .enable = false,
                .duration = Trigger::Duration{
                    .value = 1,
                    .unit = Trigger::Duration::Unit::Seconds,
                }
            },
            .maxTriggerCount = {
                .enable = false,
                .count = 1,
            },
            .maxTotalTriggerCount = {
                .enable = false,
                .count = 1,
            },
        };
        
        break;
    }
    
    case Trigger::Type::Button: {
        auto& x = t.motionButton;
        
        x.schedule = {
            .timeLimit = {
                .enable = false,
                .start = _TimeStartInit,
                .end = _TimeEndInit,
            },
            .dayLimit = {
                .enable = false,
                .cadence = Trigger::Cadence::Weekly,
                .weekDays = _WeekDaysInit,
            },
        };
        
        x.capture = {
            .count = 1,
            .interval = Trigger::Duration{
                .value = 1,
                .unit = Trigger::Duration::Unit::Seconds,
            },
            .flashLEDs = Trigger::LEDs::None,
        };
        
        x.constraints = {
            .ignoreTriggerDuration = {
                .enable = false,
                .duration = Trigger::Duration{
                    .value = 1,
                    .unit = Trigger::Duration::Unit::Seconds,
                }
            },
            .maxTriggerCount = {
                .enable = false,
                .count = 1,
            },
            .maxTotalTriggerCount = {
                .enable = false,
                .count = 1,
            },
        };
        
        break;
    }
    
    default: abort();
    }
}

struct [[gnu::packed]] Triggers {
    Trigger triggers[32];
    uint8_t triggersCount = 0;
};



@interface MonthDayObj : NSObject {
@public
    Calendar::MonthDay x;
}
@end

@implementation MonthDayObj
@end



@interface YearDayObj : NSObject {
@public
    Calendar::YearDay x;
}
@end

@implementation YearDayObj
@end




static std::string StringFromUnit(const Trigger::Duration::Unit& x) {
    using X = std::remove_reference_t<decltype(x)>;
    switch (x) {
    case X::Seconds: return "seconds";
    case X::Minutes: return "minutes";
    case X::Hours:   return "hours";
    case X::Days:    return "days";
    default:         abort();
    }
}

static Trigger::Duration::Unit UnitFromString(std::string x) {
    using X = Trigger::Duration::Unit;
    for (auto& c : x) c = std::tolower(c);
         if (x == "seconds") return X::Seconds;
    else if (x == "minutes") return X::Minutes;
    else if (x == "hours")   return X::Hours;
    else if (x == "days")    return X::Days;
    else abort();
}

static std::string StringFromCadence(const Trigger::Cadence& x) {
    using X = std::remove_reference_t<decltype(x)>;
    switch (x) {
    case X::Daily:   return "daily";
    case X::Weekly:  return "weekly";
    case X::Monthly: return "monthly";
    case X::Yearly:  return "yearly";
    default:         abort();
    }
}

static Trigger::Cadence CadenceFromString(std::string x) {
    using X = Trigger::Cadence;
    for (auto& c : x) c = std::tolower(c);
         if (x == "daily")   return X::Daily;
    else if (x == "weekly")  return X::Weekly;
    else if (x == "monthly") return X::Monthly;
    else if (x == "yearly")  return X::Yearly;
    else abort();
}

struct _TimeFormatState {
    NSCalendar* calendar = nil;
    NSDateFormatter* dateFormatterHH = nil;
    NSDateFormatter* dateFormatterHHMM = nil;
    NSDateFormatter* dateFormatterHHMMSS = nil;
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
        [x.dateFormatterHHMM setLocalizedDateFormatFromTemplate:@"hh:mm"];
        [x.dateFormatterHHMM setLenient:true];
    }
    
    {
        x.dateFormatterHHMMSS = [[NSDateFormatter alloc] init];
        [x.dateFormatterHHMMSS setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.dateFormatterHHMMSS setCalendar:x.calendar];
        [x.dateFormatterHHMMSS setTimeZone:[x.calendar timeZone]];
        [x.dateFormatterHHMMSS setLocalizedDateFormatFromTemplate:@"hh:mm:ss"];
        [x.dateFormatterHHMMSS setLenient:true];
    }
    
    return x;
}

static _TimeFormatState& _TimeFormatStateGet() {
    static _TimeFormatState x = _TimeFormatStateCreate();
    return x;
}

// 56789 -> 3:46:29 PM / 15:46:29 (depending on locale)
static std::string _TimeOfDayStringFromSeconds(uint32_t x, bool full=false) {
//    uint32_t second = x%60;
//    uint32_t minute = x/60*60;
    const uint32_t h = x/(60*60);
    x -= h*60*60;
    const uint32_t m = x/60;
    x -= m*60;
    const uint32_t s = x;
    
    NSDateComponents* comp = [NSDateComponents new];
    [comp setYear:2022];
    [comp setMonth:1];
    [comp setDay:1];
    [comp setHour:h];
    [comp setMinute:m];
    [comp setSecond:s];
    NSDate* date = [_TimeFormatStateGet().calendar dateFromComponents:comp];
    
    if (full) return [[_TimeFormatStateGet().dateFormatterHHMMSS stringFromDate:date] UTF8String];
    
    if (!s && !m) {
        return [[_TimeFormatStateGet().dateFormatterHH stringFromDate:date] UTF8String];
    } else if (!s) {
        return [[_TimeFormatStateGet().dateFormatterHHMM stringFromDate:date] UTF8String];
    } else {
        return [[_TimeFormatStateGet().dateFormatterHHMMSS stringFromDate:date] UTF8String];
    }
}

// 3:46:29 PM / 15:46:29 -> 56789
static uint32_t _SecondsFromTimeOfDayString(const std::string& x) {
    NSDate* date = [_TimeFormatStateGet().dateFormatterHHMMSS dateFromString:@(x.c_str())];
    if (!date) date = [_TimeFormatStateGet().dateFormatterHHMM dateFromString:@(x.c_str())];
    if (!date) date = [_TimeFormatStateGet().dateFormatterHH dateFromString:@(x.c_str())];
    if (!date) throw Toastbox::RuntimeError("invalid time of day: %s", x.c_str());
    
    NSDateComponents* comp = [_TimeFormatStateGet().calendar
        components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:date];
    return (uint32_t)[comp hour]*60*60 + (uint32_t)[comp minute]*60 + (uint32_t)[comp second];
}

























//static std::optional<Calendar::MonthDays> _MonthDaysForString(std::string_view x) {
//    uint32_t val = 0;
//    try {
//        Toastbox::IntForStr(val, x);
//    } catch (...) { return std::nullopt; }
//    if (val<1 || val>31) return std::nullopt;
//    return (Calendar::MonthDays)(1<<val);
//}










@interface CaptureTriggersView_ListItem : NSTableCellView
@end

@implementation CaptureTriggersView_ListItem {
@private
    IBOutlet NSImageView* _imageView;
    IBOutlet NSTextField* _titlePrefixLabel;
    IBOutlet NSTextField* _titleLabel;
    IBOutlet NSTextField* _subtitleLabel;
    IBOutlet NSTextField* _descriptionLabel;
    IBOutlet NSLayoutConstraint* _titleCenterYConstraint;
@public
    Trigger trigger;
}

static const char* _SuffixForDurationUnit(Trigger::Duration::Unit x) {
    using X = Trigger::Duration::Unit;
    switch (x) {
    case X::Seconds: return "s";
    case X::Minutes: return "m";
    case X::Hours:   return "h";
    case X::Days:    return "d";
    default:         abort();
    }
}

//        Cadence cadence = Cadence::Daily;
//        union {
//            WeekDays weekDays;
//            MonthDays monthDays;
//            YearDays yearDays;

static std::string _WeekDaysDescription(const Calendar::WeekDays& x) {
    using X = Calendar::WeekDays;
    // Only one day set
    switch (x) {
    case X::Mon:  return "Mondays";
    case X::Tue:  return "Tuesdays";
    case X::Wed:  return "Wednesdays";
    case X::Thu:  return "Thursdays";
    case X::Fri:  return "Fridays";
    case X::Sat:  return "Saturdays";
    case X::Sun:  return "Sundays";
    default:      break;
    }
    
    constexpr auto MF = (X)(std::to_underlying(X::Mon) |
                            std::to_underlying(X::Tue) |
                            std::to_underlying(X::Wed) |
                            std::to_underlying(X::Thu) |
                            std::to_underlying(X::Fri));
    if (x == MF) return "Mon-Fri";
    
    static const char* Names[] = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    
    std::string r;
    size_t i = 0;
    size_t count = 0;
    for (auto y : { X::Mon, X::Tue, X::Wed, X::Thu, X::Fri, X::Sat, X::Sun }) {
        if (std::to_underlying(x) & std::to_underlying(y)) {
            if (!r.empty()) r.append(", ");
            r.append(Names[i]);
            count++;
        }
        i++;
    }
    
    if (count>0 && count<4) return r;
    return std::to_string(count) + " days per week";
}

static std::string _MonthDaysDescription(const Calendar::MonthDays& x) {
    const size_t count = VectorFromMonthDays(x).size();
    if (count == 1) return "1 day per month";
    return std::to_string(count) + " days per month";
}

static std::string _YearDaysDescription(const Calendar::YearDays& x) {
    const size_t count = VectorFromYearDays(x).size();
    if (count == 1) return "1 day per year";
    return std::to_string(count) + " days per year";
}

template<typename T>
static std::string _CaptureDescription(const T& x) {
    std::string str = "capture " + std::to_string(x.count) + " image" + (x.count!=1 ? "s" : "");
    if (x.count>1 && x.interval.value) {
        str += " (" + std::to_string(x.interval.value) + _SuffixForDurationUnit(x.interval.unit) + " interval)";
    }
    return str;
}

- (void)updateView {
    // Image, title
    switch (trigger.type) {
    case Trigger::Type::Time:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Time-Large"]];
        [_titlePrefixLabel setStringValue: @"At"];
        [_titleLabel setStringValue: @((_TimeOfDayStringFromSeconds(trigger.time.schedule.time) + ",").c_str())];
        break;
    case Trigger::Type::Motion:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Motion-Large"]];
        [_titlePrefixLabel setStringValue: @"On"];
        [_titleLabel setStringValue:@"motion,"];
        break;
    case Trigger::Type::Button:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Button-Large"]];
        [_titlePrefixLabel setStringValue: @"On"];
        [_titleLabel setStringValue:@"button press,"];
        break;
    default:
        abort();
    }
    
    // Subtitle
    std::string subtitle;
    switch (trigger.type) {
    case Trigger::Type::Time: {
        auto& x = trigger.time;
        
        switch (x.schedule.cadence) {
        case Trigger::Cadence::Daily:   subtitle = "Daily"; break;
        case Trigger::Cadence::Weekly:  subtitle = _WeekDaysDescription(x.schedule.weekDays); break;
        case Trigger::Cadence::Monthly: subtitle = _MonthDaysDescription(x.schedule.monthDays); break;
        case Trigger::Cadence::Yearly:  subtitle = _YearDaysDescription(x.schedule.yearDays); break;
        default:                        abort();
        }
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = trigger.motionButton;
        
        if (x.schedule.dayLimit.enable) {
            switch (x.schedule.dayLimit.cadence) {
            case Trigger::Cadence::Weekly:  subtitle = _WeekDaysDescription(x.schedule.dayLimit.weekDays); break;
            case Trigger::Cadence::Monthly: subtitle = _MonthDaysDescription(x.schedule.dayLimit.monthDays); break;
            case Trigger::Cadence::Yearly:  subtitle = _YearDaysDescription(x.schedule.dayLimit.yearDays); break;
            default:                        abort();
            }
        }
        
        if (x.schedule.timeLimit.enable) {
            if (!subtitle.empty()) subtitle += ", ";
            subtitle += _TimeOfDayStringFromSeconds(x.schedule.timeLimit.start);
            subtitle += " – ";
            subtitle += _TimeOfDayStringFromSeconds(x.schedule.timeLimit.end);
        }
        
        break;
    }
    default:
        abort();
    }
    if (!subtitle.empty()) {
        [_subtitleLabel setStringValue:@(subtitle.c_str())];
        // When we have a subtitle, center title+subtitle as a group by allowing _titleCenterYConstraint to be overridden
        [_titleCenterYConstraint setPriority:NSLayoutPriorityDefaultLow];
    } else {
        [_subtitleLabel setStringValue:@""];
        // When we don't have a subtitle, center title by making _titleCenterYConstraint required
        [_titleCenterYConstraint setPriority:NSLayoutPriorityRequired];
    }
    
    // Description
    switch (trigger.type) {
    case Trigger::Type::Time: {
        auto& x = trigger.time;
        [_descriptionLabel setStringValue:@(_CaptureDescription(x.capture).c_str())];
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = trigger.motionButton;
        [_descriptionLabel setStringValue:@(_CaptureDescription(x.capture).c_str())];
        break;
    }
    default:
        abort();
    }
}

@end


#define ListItem CaptureTriggersView_ListItem




























@interface CaptureTriggersView_ContainerSubview : NSView
@end

@implementation CaptureTriggersView_ContainerSubview {
@public
    IBOutlet NSView* alignView;
}
@end

#define ContainerSubview CaptureTriggersView_ContainerSubview


@implementation CaptureTriggersView {
@public
    IBOutlet NSView* _nibView;
    
    IBOutlet NSTableView* _tableView;
    IBOutlet NSView* _containerView;
    IBOutlet ContainerSubview* _detailView;
    IBOutlet ContainerSubview* _noSelectionView;
    
    // Schedule
    IBOutlet NSView*            _schedule_ContainerView;
    
    IBOutlet ContainerSubview*  _schedule_Time_View;
    IBOutlet NSTextField*       _schedule_Time_TimeField;
    IBOutlet NSView*            _schedule_Time_DaySelectorContainerView;
    IBOutlet NSPopUpButton*     _schedule_Time_CadenceMenu;
    
    IBOutlet ContainerSubview*  _schedule_Motion_View;
    IBOutlet NSButton*          _schedule_Motion_LimitTime_Checkbox;
    IBOutlet NSTextField*       _schedule_Motion_LimitTime_TimeStartField;
    IBOutlet NSTextField*       _schedule_Motion_LimitTime_TimeEndField;
    IBOutlet NSButton*          _schedule_Motion_LimitDays_Checkbox;
    IBOutlet NSPopUpButton*     _schedule_Motion_LimitDays_CadenceMenu;
    IBOutlet NSView*            _schedule_Motion_DaySelectorContainerView;
    
    IBOutlet ContainerSubview*   _weekDaySelector_View;
    IBOutlet NSSegmentedControl* _weekDaySelector_Control;
    
    IBOutlet ContainerSubview*  _monthDaySelector_View;
    IBOutlet NSTokenField*      _monthDaySelector_Field;
    
    IBOutlet ContainerSubview*  _yearDaySelector_View;
    IBOutlet NSTokenField*      _yearDaySelector_Field;
    
    // Capture
    IBOutlet NSTextField*        _capture_CountField;
    IBOutlet NSTextField*        _capture_IntervalLabel;
    IBOutlet NSTextField*        _capture_IntervalField;
    IBOutlet NSPopUpButton*      _capture_IntervalUnitMenu;
    IBOutlet NSSegmentedControl* _capture_FlashLEDsControl;
    
    // Constraints
    IBOutlet NSView*            _constraints_ContainerView;
    
    IBOutlet ContainerSubview*  _constraints_Motion_View;
    IBOutlet NSButton*          _constraints_Motion_IgnoreTrigger_Checkbox;
    IBOutlet NSTextField*       _constraints_Motion_IgnoreTrigger_DurationField;
    IBOutlet NSPopUpButton*     _constraints_Motion_IgnoreTrigger_DurationUnitMenu;
    IBOutlet NSButton*          _constraints_Motion_MaxTriggerCount_Checkbox;
    IBOutlet NSTextField*       _constraints_Motion_MaxTriggerCount_Field;
    
    IBOutlet NSButton*      _constraints_MaxTotalTriggerCount_Checkbox;
    IBOutlet NSTextField*   _constraints_MaxTotalTriggerCount_Field;
    
    std::vector<ListItem*> _items;
    bool _actionViewChangedUnderway;
}

static ListItem* _ListItemAdd(CaptureTriggersView* self, Trigger::Type type) {
    assert(self);
    NSTableView* tv = self->_tableView;
    ListItem* it = [tv makeViewWithIdentifier:NSStringFromClass([ListItem class]) owner:nil];
    Trigger& t = it->trigger;
    _InitTrigger(t, type);
    [it updateView];
    
    self->_items.push_back(it);
    NSIndexSet* idxs = [NSIndexSet indexSetWithIndex:self->_items.size()-1];
    [tv insertRowsAtIndexes:idxs withAnimation:NSTableViewAnimationEffectNone];
    [tv selectRowIndexes:idxs byExtendingSelection:false];
    return it;
}

static void _ListItemRemove(CaptureTriggersView* self, size_t idx) {
    assert(self);
    assert(idx < self->_items.size());
    NSTableView* tv = self->_tableView;
    
    // Remove item
    {
        NSIndexSet* idxs = [NSIndexSet indexSetWithIndex:idx];
        self->_items.erase(self->_items.begin()+idx);
        [tv removeRowsAtIndexes:idxs withAnimation:NSTableViewAnimationEffectNone];
    }
    
    // Update selection
    if (!self->_items.empty()) {
        NSIndexSet* idxs = [NSIndexSet indexSetWithIndex:std::min(self->_items.size()-1, idx)];
        [tv selectRowIndexes:idxs byExtendingSelection:false];
    }
}

static void _Init(CaptureTriggersView* self) {
    // Load view from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        NSView* nibView = self->_nibView;
        [nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:nibView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
    }
    
    [self->_tableView reloadData];
//    _ListItemAdd(self, Trigger::Type::Time);
//    _ListItemAdd(self, Trigger::Type::Motion);
    _ListItemAdd(self, Trigger::Type::Button);
    
    {
        NSMutableCharacterSet* set = [[self->_monthDaySelector_Field tokenizingCharacterSet] mutableCopy];
        [set addCharactersInString:@" "];
        [self->_monthDaySelector_Field setTokenizingCharacterSet:set];
    }
    
    [self->_yearDaySelector_Field setPlaceholderString:@(Calendar::YearDayPlaceholderString().c_str())];
    
    _ContainerSubviewAdd(self->_containerView, self->_detailView);
    _ContainerSubviewAdd(self->_containerView, self->_noSelectionView);
}

// MARK: - Creation

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _Init(self);
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _Init(self);
    return self;
}

static void _ContainerSubviewAdd(NSView* container, ContainerSubview* subview, NSView* alignView=nil) {
    [container addSubview:subview];
    
    NSMutableArray* constraints = [NSMutableArray new];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[subview]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(subview)]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[subview]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(subview)]];
    
    if (alignView) {
        [constraints addObject:[[subview->alignView leadingAnchor] constraintEqualToAnchor:[alignView leadingAnchor]]];
    }
    
    [NSLayoutConstraint activateConstraints:constraints];
}

static void _ContainerSubviewSet(NSView* container, ContainerSubview* subview, NSView* alignView=nil) {
    // Either subview==nil, or existence of `alignView` matches existence of `subview->alignView`
    assert(!subview || ((bool)alignView == (bool)subview->alignView));
    // Short-circuit if `subview` is already the subview of `container`
    if ([subview superview] == container) return;
    
    [subview removeFromSuperview];
    [container setSubviews:@[]];
    if (!subview) return;
    
    _ContainerSubviewAdd(container, subview, alignView);
}

template<bool T_Forward>
static void _Copy(bool& x, NSButton* checkbox) {
    if constexpr (T_Forward) {
        [checkbox setState:(x ? NSControlStateValueOn : NSControlStateValueOff)];
    } else {
        x = ([checkbox state] == NSControlStateValueOn);
    }
}

template<bool T_Forward>
static void _Copy(Trigger::Cadence& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        std::string xstr = StringFromCadence(x);
        xstr[0] = std::toupper(xstr[0]);
        NSMenuItem* item = [menu itemWithTitle:@(xstr.c_str())];
        #warning TODO: is this a good behavior?
        if (!item) item = [menu itemAtIndex:0];
        [menu selectItem:item];
    
    } else {
        NSString* str = [menu titleOfSelectedItem];
        assert(str);
        x = CadenceFromString([str UTF8String]);
    }
}

template<bool T_Forward>
static void _CopyTime(uint32_t& x, NSTextField* field) {
    if constexpr (T_Forward) {
        [field setStringValue:@(_TimeOfDayStringFromSeconds(x).c_str())];
    } else {
        x = _SecondsFromTimeOfDayString([[field stringValue] UTF8String]);
    }
}

template<bool T_Forward>
static void _Copy(uint32_t& x, NSTextField* field) {
    if constexpr (T_Forward) {
        [field setObjectValue:@(x)];
    } else {
        x = (uint32_t)[field integerValue];
    }
}

template<bool T_Forward>
static void _Copy(Trigger::Duration::Unit& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        [menu selectItemWithTitle:@(StringFromUnit(x).c_str())];
    } else {
        const std::string xstr = [[menu titleOfSelectedItem] UTF8String];
        x = UnitFromString([[menu titleOfSelectedItem] UTF8String]);
    }
}

template<bool T_Forward>
static void _Copy(Calendar::WeekDays& x, NSSegmentedControl* control) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        size_t idx = 0;
        for (auto y : { X::Mon, X::Tue, X::Wed, X::Thu, X::Fri, X::Sat, X::Sun }) {
            [control setSelected:(std::to_underlying(x) & std::to_underlying(y)) forSegment:idx];
            idx++;
        }
    } else {
        std::underlying_type_t<X> r = 0;
        size_t idx = 0;
        for (auto y : { X::Mon, X::Tue, X::Wed, X::Thu, X::Fri, X::Sat, X::Sun }) {
            r |= ([control isSelectedForSegment:idx] ? std::to_underlying(y) : 0);
            idx++;
        }
        x = static_cast<X>(r);
    }
}

template<bool T_Forward>
static void _Copy(Calendar::MonthDays& x, NSTokenField* field) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        NSMutableArray* tokens = [NSMutableArray new];
        std::vector<Calendar::MonthDay> days = VectorFromMonthDays(x);
        for (Calendar::MonthDay day : days) {
            MonthDayObj* x = [MonthDayObj new];
            x->x = day;
            [tokens addObject:x];
        }
        [field setObjectValue:tokens];
    
    } else {
        NSArray* tokens = Toastbox::CastOrNull<NSArray*>([field objectValue]);
        std::vector<Calendar::MonthDay> days;
        for (id t : tokens) {
            MonthDayObj* x = Toastbox::CastOrNull<MonthDayObj*>(t);
            if (!x) continue;
            days.push_back(x->x);
        }
        x = MonthDaysFromVector(days);
    }
}

template<bool T_Forward>
static void _Copy(Calendar::YearDays& x, NSTokenField* field) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        NSMutableArray* tokens = [NSMutableArray new];
        std::vector<Calendar::YearDay> days = VectorFromYearDays(x);
        for (Calendar::YearDay day : days) {
            YearDayObj* x = [YearDayObj new];
            x->x = day;
            [tokens addObject:x];
        }
        [field setObjectValue:tokens];
    
    } else {
        NSArray* tokens = Toastbox::CastOrNull<NSArray*>([field objectValue]);
        std::vector<Calendar::YearDay> days;
        for (id t : tokens) {
            YearDayObj* x = Toastbox::CastOrNull<YearDayObj*>(t);
            if (!x) continue;
            days.push_back(x->x);
        }
        x = YearDaysFromVector(days);
    }
}

template<bool T_Forward>
static void _Copy(Trigger::LEDs& x, NSSegmentedControl* control) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        size_t idx = 0;
        for (auto y : { X::Green, X::Red }) {
            [control setSelected:(std::to_underlying(x) & std::to_underlying(y)) forSegment:idx];
            idx++;
        }
    } else {
        std::underlying_type_t<X> r = 0;
        size_t idx = 0;
        for (auto y : { X::Green, X::Red }) {
            r |= ([control isSelectedForSegment:idx] ? std::to_underlying(y) : 0);
            idx++;
        }
        x = static_cast<X>(r);
    }
}

template<bool T_Forward>
static void _Copy(Trigger& trigger, CaptureTriggersView* view) {
    auto& y = *view;
    switch (trigger.type) {
    case Trigger::Type::Time: {
        auto& x = trigger.time;
        
        // Schedule
        {
            if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_ContainerView, y._schedule_Time_View);
            
            _CopyTime<T_Forward>(x.schedule.time, y._schedule_Time_TimeField);
            _Copy<T_Forward>(x.schedule.cadence, y._schedule_Time_CadenceMenu);
            switch (x.schedule.cadence) {
            case Trigger::Cadence::Daily:
                if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_Time_DaySelectorContainerView, nil);
                break;
            case Trigger::Cadence::Weekly:
                if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_Time_DaySelectorContainerView, y._weekDaySelector_View, y._schedule_Time_CadenceMenu);
                _Copy<T_Forward>(x.schedule.weekDays, y._weekDaySelector_Control);
                break;
            case Trigger::Cadence::Monthly:
                if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_Time_DaySelectorContainerView, y._monthDaySelector_View, y._schedule_Time_CadenceMenu);
                _Copy<T_Forward>(x.schedule.monthDays, y._monthDaySelector_Field);
                break;
            case Trigger::Cadence::Yearly:
                if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_Time_DaySelectorContainerView, y._yearDaySelector_View, y._schedule_Time_CadenceMenu);
                _Copy<T_Forward>(x.schedule.yearDays, y._yearDaySelector_Field);
                break;
            default:
                abort();
            }
        }
        
        // Capture
        {
            _Copy<T_Forward>(x.capture.count, y._capture_CountField);
            _Copy<T_Forward>(x.capture.interval.value, y._capture_IntervalField);
            _Copy<T_Forward>(x.capture.interval.unit, y._capture_IntervalUnitMenu);
            
            if constexpr (T_Forward) {
                [y._capture_IntervalLabel setHidden:x.capture.count<2];
                [y._capture_IntervalField setHidden:x.capture.count<2];
                [y._capture_IntervalUnitMenu setHidden:x.capture.count<2];
            }
            
            _Copy<T_Forward>(x.capture.flashLEDs, y._capture_FlashLEDsControl);
        }
        
        // Limits
        {
            if constexpr (T_Forward) _ContainerSubviewSet(y._constraints_ContainerView, nil);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.enable, y._constraints_MaxTotalTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.count, y._constraints_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = trigger.motionButton;
        
        // Schedule
        {
            if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_ContainerView, y._schedule_Motion_View);
            
            _Copy<T_Forward>(x.schedule.timeLimit.enable, y._schedule_Motion_LimitTime_Checkbox);
            _CopyTime<T_Forward>(x.schedule.timeLimit.start, y._schedule_Motion_LimitTime_TimeStartField);
            _CopyTime<T_Forward>(x.schedule.timeLimit.end, y._schedule_Motion_LimitTime_TimeEndField);
            _Copy<T_Forward>(x.schedule.dayLimit.enable, y._schedule_Motion_LimitDays_Checkbox);
            _Copy<T_Forward>(x.schedule.dayLimit.cadence, y._schedule_Motion_LimitDays_CadenceMenu);
            
            switch (x.schedule.dayLimit.cadence) {
            case Trigger::Cadence::Daily:
            case Trigger::Cadence::Weekly:
                if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_Motion_DaySelectorContainerView, y._weekDaySelector_View, y._schedule_Motion_LimitTime_TimeStartField);
                _Copy<T_Forward>(x.schedule.dayLimit.weekDays, y._weekDaySelector_Control);
                break;
            case Trigger::Cadence::Monthly:
                if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_Motion_DaySelectorContainerView, y._monthDaySelector_View, y._schedule_Motion_LimitTime_TimeStartField);
                _Copy<T_Forward>(x.schedule.dayLimit.monthDays, y._monthDaySelector_Field);
                break;
            case Trigger::Cadence::Yearly:
                if constexpr (T_Forward) _ContainerSubviewSet(y._schedule_Motion_DaySelectorContainerView, y._yearDaySelector_View, y._schedule_Motion_LimitTime_TimeStartField);
                _Copy<T_Forward>(x.schedule.dayLimit.yearDays, y._yearDaySelector_Field);
                break;
            default:
                abort();
            }
        }
        
        // Capture
        {
            _Copy<T_Forward>(x.capture.count, y._capture_CountField);
            _Copy<T_Forward>(x.capture.interval.value, y._capture_IntervalField);
            _Copy<T_Forward>(x.capture.interval.unit, y._capture_IntervalUnitMenu);
            
            if constexpr (T_Forward) {
                [y._capture_IntervalLabel setHidden:x.capture.count<2];
                [y._capture_IntervalField setHidden:x.capture.count<2];
                [y._capture_IntervalUnitMenu setHidden:x.capture.count<2];
            }
            
            _Copy<T_Forward>(x.capture.flashLEDs, y._capture_FlashLEDsControl);
        }
        
        // Limits
        {
            if constexpr (T_Forward) _ContainerSubviewSet(y._constraints_ContainerView, y._constraints_Motion_View, y._constraints_MaxTotalTriggerCount_Field);
            
            _Copy<T_Forward>(x.constraints.ignoreTriggerDuration.enable, y._constraints_Motion_IgnoreTrigger_Checkbox);
            _Copy<T_Forward>(x.constraints.ignoreTriggerDuration.duration.value, y._constraints_Motion_IgnoreTrigger_DurationField);
            _Copy<T_Forward>(x.constraints.ignoreTriggerDuration.duration.unit, y._constraints_Motion_IgnoreTrigger_DurationUnitMenu);
            
            _Copy<T_Forward>(x.constraints.maxTriggerCount.enable, y._constraints_Motion_MaxTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTriggerCount.count, y._constraints_Motion_MaxTriggerCount_Field);
            
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.enable, y._constraints_MaxTotalTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.count, y._constraints_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    default:
        abort();
    }
}


- (void)_storeViewToModel:(Trigger&)trigger {
//    if (NSText* x = Toastbox::CastOrNull<NSText*>([[self window] firstResponder])) {
//        [x selectAll:nil];
//    }
//    [[[self window] firstResponder] insertNewline:nil];
//    NSLog(@"%@", [[[self window] firstResponder] insertNewline:nil]);
//    [[self window] firstResponder];
//    [[self window] endEditingFor:nil];
//    [[self window] firstResponder] endEditing;
    _Copy<false>(trigger, self);
}

- (void)_loadViewFromModel:(Trigger&)trigger {
    _Copy<true>(trigger, self);
    [[self window] recalculateKeyViewLoop];
}





//static void _Copy(const Trigger::Duration& x, NSTextField* field, NSPopUpButton* menu) {
//    using X = std::remove_reference_t<decltype(x)>;
//    [field setObjectValue:@(x.value)];
//    [menu selectItemAtIndex:(NSInteger)x.unit];
//}
//
//static void _Store(Trigger::Duration& x, NSTextField* field, NSPopUpButton* menu) {
//    using X = std::remove_reference_t<decltype(x)>;
//    x.value = (uint32_t)[field integerValue];
//    x.unit = (Trigger::Duration::Unit)[menu indexOfSelectedItem];
//}








//static void _MonthDaysLoad(const Calendar::MonthDays& days, NSSegmentedControl* control) {
//    using D = Calendar::WeekDays_;
//    size_t idx = 0;
//    for (Calendar::WeekDays day : { D::Mon, D::Tue, D::Wed, D::Thu, D::Fri, D::Sat, D::Sun }) {
//        [control setSelected:(days & day) forSegment:idx];
//        idx++;
//    }
//}
//
//static void _MonthDaysStore(Calendar::MonthDays& days, NSSegmentedControl* control) {
//    using D = Calendar::WeekDays_;
//    size_t idx = 0;
//    for (Calendar::WeekDays day : { D::Mon, D::Tue, D::Wed, D::Thu, D::Fri, D::Sat, D::Sun }) {
//        days |= ([control isSelectedForSegment:idx] ? day : 0);
//        idx++;
//    }
//}

// MARK: - Actions

- (ListItem*)_selectedItem {
    NSInteger idx = [_tableView selectedRow];
    if (idx < 0) return nil;
    return _items.at(idx);
}

static void _StoreLoad(CaptureTriggersView* self, bool initCadence=false) {
    // Prevent re-entry, because our committing logic can trigger multiple calls
    if (self->_actionViewChangedUnderway) return;
    self->_actionViewChangedUnderway = true;
    Defer( self->_actionViewChangedUnderway = false );
    
    NSLog(@"_actionViewChanged");
    ListItem* it = [self _selectedItem];
    if (!it) return;
//    NSResponder* responder = [[self window] firstResponder];
//    NSLog(@"BEFORE: %@", responder);
    
    // Commit editing the active editor
    if (NSText* x = Toastbox::CastOrNull<NSText*>([[self window] firstResponder])) {
        // We call -insertNewline twice because NSTokenField has 2 sequential states
        // that the return key transitions through, and we want to transition through
        // both to get to the final "select all" state.
        [x insertNewline:nil];
        [x insertNewline:nil];
    }
    
    [self _storeViewToModel:it->trigger];
    
    if (initCadence) {
        _InitTriggerScheduleCadence(it->trigger);
    }
    
    [self _loadViewFromModel:it->trigger];
//    if ([[self window] firstResponder] != responder) {
//        [[self window] makeFirstResponder:responder];
//    }
//    NSLog(@"AFTER: %@", [[self window] firstResponder]);
//    [[self window] makeFirstResponder:responder];
    [it updateView];
}

- (IBAction)_actionViewChanged:(id)sender {
    _StoreLoad(self);
}

- (IBAction)_actionScheduleCadenceChanged:(id)sender {
    _StoreLoad(self, true);
}

- (IBAction)_actionAddTimeTrigger:(id)sender {
    _ListItemAdd(self, Trigger::Type::Time);
}

- (IBAction)_actionAddMotionTrigger:(id)sender {
    _ListItemAdd(self, Trigger::Type::Motion);
}

- (IBAction)_actionAddButtonTrigger:(id)sender {
    _ListItemAdd(self, Trigger::Type::Button);
}

- (IBAction)_actionRemove:(id)sender {
    NSInteger idx = [_tableView selectedRow];
    if (idx < 0) return;
    _ListItemRemove(self, idx);
}

// MARK: - Table View Data Source / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    NSLog(@"numberOfRowsInTableView: %@", @(_items.size()));
    return _items.size();
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    NSLog(@"viewForTableColumn: %@", _items.at(row));
    return _items.at(row);
}

- (void)tableViewSelectionDidChange:(NSNotification*)note {
    NSInteger idx = [_tableView selectedRow];
    ListItem* item = (idx>=0 ? _items.at(idx) : nil);
    
    [_noSelectionView setHidden:(bool)item];
    [_detailView setHidden:!item];
    if (!item) return;
    
    [self _loadViewFromModel:item->trigger];
}












- (NSArray*)tokenField:(NSTokenField*)field shouldAddObjects:(NSArray*)tokens atIndex:(NSUInteger)index {
//    NSLog(@"%@", NSStringFromSelector(_cmd));
//    return nil;
    
    if (field == _monthDaySelector_Field) {
        NSLog(@"_monthDaySelector_Field");
        
        NSMutableArray* filtered = [NSMutableArray new];
        for (NSString* t : tokens) {
            auto day = Calendar::MonthDayFromString([t UTF8String]);
            if (!day) continue;
            MonthDayObj* obj = [MonthDayObj new];
            obj->x = *day;
            [filtered addObject:obj];
        }
        return filtered;
    
    } else if (field == _yearDaySelector_Field) {
        NSLog(@"_yearDaySelector_Field");
        
        NSMutableArray* filtered = [NSMutableArray new];
        for (NSString* x : tokens) {
            auto day = Calendar::YearDayFromString([x UTF8String]);
            if (!day) continue;
            YearDayObj* obj = [YearDayObj new];
            obj->x = *day;
            [filtered addObject:obj];
        }
        return filtered;
    
    } else {
        abort();
    }
}

- (NSString*)tokenField:(NSTokenField*)field displayStringForRepresentedObject:(id)obj {
    if (field == _monthDaySelector_Field) {
        if (MonthDayObj* x = Toastbox::CastOrNull<MonthDayObj*>(obj)) {
            return @(Calendar::StringFromMonthDay(x->x).c_str());
        }
        return obj;
    
    } else if (field == _yearDaySelector_Field) {
        if (YearDayObj* x = Toastbox::CastOrNull<YearDayObj*>(obj)) {
            return @(Calendar::StringFromYearDay(x->x).c_str());
        }
        return obj;
    
    } else {
        abort();
    }
}

//- (NSString*)tokenField:(NSTokenField*)field editingStringForRepresentedObject:(id)obj {
//    if (field == _monthDaySelector_Field) {
//        return nil;
//    
//    } else if (field == _yearDaySelector_Field) {
//        return nil;
//    
//    } else {
//        abort();
//    }
//}

//- (id)tokenField:(NSTokenField*)field representedObjectForEditingString:(NSString*)str {
//    if (field == _monthDaySelector_Field) {
//        return nil;
//    
//    } else if (field == _yearDaySelector_Field) {
//        return nil;
//    
//    } else {
//        abort();
//    }
//}

@end
