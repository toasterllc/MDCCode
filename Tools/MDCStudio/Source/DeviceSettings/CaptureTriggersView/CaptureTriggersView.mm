#import "CaptureTriggersView.h"
#import <vector>
#import <optional>
#import <sstream>
#import <iomanip>
#import <cmath>
#import <string>
#import <set>
#import "DeviceSettings.h"
#import "Calendar.h"
#import "Toastbox/Mac/Util.h"
#import "Toastbox/RuntimeError.h"
#import "Toastbox/NumForStr.h"
#import "Toastbox/String.h"
#import "Toastbox/Defer.h"
#import "Code/Shared/Clock.h"
using namespace MDCStudio;
using namespace DeviceSettings;

#warning TODO: add version, or is the version specified by whatever contains Trigger instances?

constexpr Calendar::TimeOfDay _TimeStartInit(32400); // 9 AM
constexpr Calendar::TimeOfDay _TimeEndInit  (61200); // 5 PM
//static const Calendar::DaysOfWeek _DaysOfWeekInit = Calendar::DaysOfWeekFromVector({
//    Calendar::DayOfWeek_::Mon,
//    Calendar::DayOfWeek_::Tue,
//    Calendar::DayOfWeek_::Wed,
//    Calendar::DayOfWeek_::Thu,
//    Calendar::DayOfWeek_::Fri,
//});

static const Calendar::DaysOfWeek _DaysOfWeekMonFri = {
    Calendar::DaysOfWeekMask(date::Monday)    |
    Calendar::DaysOfWeekMask(date::Tuesday)   |
    Calendar::DaysOfWeekMask(date::Wednesday) |
    Calendar::DaysOfWeekMask(date::Thursday)  |
    Calendar::DaysOfWeekMask(date::Friday)
};

static const Calendar::DaysOfWeek _DaysOfWeekInit = _DaysOfWeekMonFri;

static const Calendar::DaysOfYear _DaysOfYearInit = Calendar::DaysOfYearFromVector({
    Calendar::DayOfYear{Calendar::MonthOfYear(9),  Calendar::DayOfMonth(20)},
    Calendar::DayOfYear{Calendar::MonthOfYear(12), Calendar::DayOfMonth(31)},
});

static constexpr DayInterval _DayIntervalInit = DayInterval{ 2 };

//static Repeat& _TriggerRepeatGet(CaptureTrigger& t) {
//    switch (t.type) {
//    case Type::Time:   return t.time.schedule.repeat;
//    case Type::Motion: return t.motion.schedule.repeat;
//    default:                    abort();
//    }
//}

static void _TriggerInitRepeat(Repeat& x) {
    using X = Repeat::Type;
    switch (x.type) {
    case X::Daily:
        break;
    case X::DaysOfWeek:
        x.DaysOfWeek = _DaysOfWeekInit;
        break;
    case X::DaysOfYear:
        x.DaysOfYear = _DaysOfYearInit;
        break;
    case X::DayInterval:
        x.DayInterval = _DayIntervalInit;
        break;
    default:
        abort();
    }
}

static void _TriggerInit(CaptureTrigger& t, CaptureTrigger::Type type) {
    t.type = type;
    switch (t.type) {
    case CaptureTrigger::Type::Time: {
        auto& x = t.time;
        
        x.schedule = {
            .time = _TimeStartInit,
            .repeat = {
                .type = Repeat::Type::Daily,
            },
        };
        
        x.capture = {
            .count = 1,
            .interval = DeviceSettings::Duration{
                .value = 5,
                .unit = DeviceSettings::Duration::Unit::Seconds,
            },
            .flashLEDs = LEDs::None,
        };
        
        break;
    }
    
    case CaptureTrigger::Type::Motion: {
        auto& x = t.motion;
        
        x.schedule = {
            .timeRange = {
                .enable = false,
                .start = _TimeStartInit,
                .end = _TimeEndInit,
            },
            .repeat = {
                .type = Repeat::Type::Daily,
            },
        };
        
        x.capture = {
            .count = 1,
            .interval = DeviceSettings::Duration{
                .value = 5,
                .unit = DeviceSettings::Duration::Unit::Seconds,
            },
            .flashLEDs = LEDs::None,
        };
        
        x.constraints = {
            .suppressDuration = {
                .enable = false,
                .duration = DeviceSettings::Duration{
                    .value = 5,
                    .unit = DeviceSettings::Duration::Unit::Minutes,
                }
            },
            .maxTriggerCount = {
                .enable = false,
                .count = 5,
            },
        };
        
        break;
    }
    
    case CaptureTrigger::Type::Button: {
        auto& x = t.button;
        
        x.capture = {
            .count = 1,
            .interval = DeviceSettings::Duration{
                .value = 5,
                .unit = DeviceSettings::Duration::Unit::Seconds,
            },
            .flashLEDs = LEDs::None,
        };
        
        break;
    }
    
    default: abort();
    }
}

static CaptureTrigger _TriggerMake(CaptureTrigger::Type type) {
    CaptureTrigger x;
    _TriggerInit(x, type);
    return x;
}

@interface DayOfMonthObj : NSObject {
@public
    Calendar::DayOfMonth x;
}
@end

@implementation DayOfMonthObj
@end



@interface DayOfYearObj : NSObject {
@public
    Calendar::DayOfYear x;
}
@end

@implementation DayOfYearObj
@end




static std::string StringFromUnit(const DeviceSettings::Duration::Unit& x) {
    using X = std::remove_reference_t<decltype(x)>;
    switch (x) {
    case X::Seconds: return "seconds";
    case X::Minutes: return "minutes";
    case X::Hours:   return "hours";
    case X::Days:    return "days";
    default:         abort();
    }
}

static DeviceSettings::Duration::Unit UnitFromString(std::string x) {
    using X = DeviceSettings::Duration::Unit;
    for (auto& c : x) c = std::tolower(c);
         if (x == "seconds") return X::Seconds;
    else if (x == "minutes") return X::Minutes;
    else if (x == "hours")   return X::Hours;
    else if (x == "days")    return X::Days;
    else abort();
}

static std::string StringFromRepeatType(const Repeat::Type& x) {
    using X = std::remove_reference_t<decltype(x)>;
    switch (x) {
    case X::Daily:       return "every day";
    case X::DaysOfWeek:    return "on days";
    case X::DaysOfYear:    return "on dates";
    case X::DayInterval: return "on interval";
    default:             abort();
    }
}

static Repeat::Type RepeatTypeFromString(std::string x) {
    using X = Repeat::Type;
    for (auto& c : x) c = std::tolower(c);
         if (x == "every day")     return X::Daily;
    else if (x == "on days")       return X::DaysOfWeek;
    else if (x == "on dates")      return X::DaysOfYear;
    else if (x == "on interval")   return X::DayInterval;
    else abort();
}































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
    CaptureTrigger trigger;
}

static const char* _SuffixForDurationUnit(DeviceSettings::Duration::Unit x) {
    using X = DeviceSettings::Duration::Unit;
    switch (x) {
    case X::Seconds: return "s";
    case X::Minutes: return "m";
    case X::Hours:   return "h";
    case X::Days:    return "d";
    default:         abort();
    }
}

static std::string _DaysOfWeekDescription(const Calendar::DaysOfWeek& x) {
    using namespace Calendar;
    
    // Monday-Friday special case
    if (x.x == _DaysOfWeekMonFri.x) return "Mon-Fri";
    
    const auto days = VectorFromDaysOfWeek(x);
    
    // Only one day set
    if (days.size() == 1) {
        const DayOfWeek d = days.at(0);
        if (d == date::Sunday)    return "Sundays";
        if (d == date::Monday)    return "Mondays";
        if (d == date::Tuesday)   return "Tuesdays";
        if (d == date::Wednesday) return "Wednesdays";
        if (d == date::Thursday)  return "Thursdays";
        if (d == date::Friday)    return "Fridays";
        if (d == date::Saturday)  return "Saturdays";
        abort();
    }
    
    // 0 or >3 days set
    if (days.empty() || days.size()>3) return std::to_string(days.size()) + " days per week";
    
    // 1-3 days set
    std::string r;
    for (auto day : days) {
        if (!r.empty()) r.append(", ");
        r.append(StringForDayOfWeek(day));
    }
    return r;
}

static std::string _DaysOfYearDescription(const Calendar::DaysOfYear& x) {
    const size_t count = VectorFromDaysOfYear(x).size();
    if (count == 1) return "1 day per year";
    return std::to_string(count) + " days per year";
}

static std::string _DayIntervalDescription(const DayInterval& x) {
    if (x.count() == 0) return "every day";
    if (x.count() == 1) return "every day";
    if (x.count() == 2) return "every other day";
    return "every " + std::to_string(x.count()) + " days";
}

static std::string _DayIntervalDetailedDescription(const DayInterval& x) {
    if (x.count() == 0) return "every day";
    if (x.count() == 1) return "every day";
    if (x.count() == 2) return "every other day";
    return "1 day on, " + std::to_string(x.count()-1) + " days off";
}

static std::string _Capitalize(std::string x) {
    if (!x.empty()) {
        x[0] = std::toupper(x[0]);
    }
    return x;
}

static std::string _RepeatDescription(const Repeat& x) {
    using T = Repeat::Type;
    std::string s;
    switch (x.type) {
    case T::Daily:       return "daily";
    case T::DaysOfWeek:    return _DaysOfWeekDescription(x.DaysOfWeek);
    case T::DaysOfYear:    return _DaysOfYearDescription(x.DaysOfYear);
    case T::DayInterval: return _DayIntervalDescription(x.DayInterval);
    default:             abort();
    }
}

static std::string _StringFromFloat(float x, int maxDecimalPlaces=1) {
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

static float _FloatFromString(std::string_view x) {
    return Toastbox::FloatForStr<float>(x);
}

static std::string _CaptureDescription(const Capture& x) {
    std::stringstream ss;
    ss << "capture " << x.count << " image" << (x.count!=1 ? "s" : "");
    if (x.count>1 && x.interval.value>0) {
        ss << " (" << _StringFromFloat(x.interval.value);
        ss << _SuffixForDurationUnit(x.interval.unit) << " interval)";
    }
    return ss.str();
}

static std::string _TimeRangeDescription(Calendar::TimeOfDay start, Calendar::TimeOfDay end) {
    std::string r;
    r += Calendar::StringFromTimeOfDay(start);
    r += " – ";
    r += Calendar::StringFromTimeOfDay(end);
    return r;
}

- (void)updateView {
    // Image, title
    switch (trigger.type) {
    case CaptureTrigger::Type::Time:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Time-Large"]];
        [_titlePrefixLabel setStringValue: @"At"];
        [_titleLabel setStringValue: @((Calendar::StringFromTimeOfDay(trigger.time.schedule.time) + ",").c_str())];
        break;
    case CaptureTrigger::Type::Motion:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Motion-Large"]];
        [_titlePrefixLabel setStringValue: @"On"];
        [_titleLabel setStringValue:@"motion,"];
        break;
    case CaptureTrigger::Type::Button:
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
    case CaptureTrigger::Type::Time: {
        auto& x = trigger.time;
        subtitle = _Capitalize(_RepeatDescription(x.schedule.repeat));
        break;
    }
    
    case CaptureTrigger::Type::Motion: {
        auto& x = trigger.motion;
        auto& repeat = trigger.motion.schedule.repeat;
        if (repeat.type != Repeat::Type::Daily) {
            subtitle = _Capitalize(_RepeatDescription(repeat));
        }
        
        if (x.schedule.timeRange.enable) {
            if (!subtitle.empty()) subtitle += ", ";
            subtitle += _TimeRangeDescription(x.schedule.timeRange.start, x.schedule.timeRange.end);
        }
        break;
    }
    
    case CaptureTrigger::Type::Button: {
        break;
    }
    
    default:
        break;
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
    case CaptureTrigger::Type::Time: {
        auto& x = trigger.time;
        [_descriptionLabel setStringValue:@(_CaptureDescription(x.capture).c_str())];
        break;
    }
    
    case CaptureTrigger::Type::Motion: {
        auto& x = trigger.motion;
        [_descriptionLabel setStringValue:@(_CaptureDescription(x.capture).c_str())];
        break;
    }
    
    case CaptureTrigger::Type::Button: {
        auto& x = trigger.button;
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
    IBOutlet NSView*            _nibView;
    IBOutlet NSTableView*       _tableView;
    IBOutlet NSView*            _containerView;
    IBOutlet ContainerSubview*  _detailView;
    IBOutlet NSControl*         _addButton;
    IBOutlet NSControl*         _removeButton;
    IBOutlet NSView*            _noTriggersView;
    
    IBOutlet NSView*             _separatorLine;
    IBOutlet NSLayoutConstraint* _separatorLineOffset;
    
    // Schedule
    IBOutlet NSView*            _schedule_ContainerView;
    
    IBOutlet ContainerSubview*  _schedule_Time_View;
    IBOutlet NSTextField*       _schedule_Time_TimeField;
    IBOutlet NSView*            _schedule_Time_RepeatContainerView;
    
    IBOutlet NSView*            _schedule_Motion_RepeatContainerView;
    IBOutlet NSPopUpButton*     _schedule_Motion_TimeRange_Menu;
    IBOutlet NSTextField*       _schedule_Motion_TimeRange_TimeStartField;
    IBOutlet NSTextField*       _schedule_Motion_TimeRange_TimeEndField;
    
    IBOutlet ContainerSubview*  _repeat_View;
    IBOutlet NSTextField*       _repeat_MenuLabel;
    IBOutlet NSPopUpButton*     _repeat_Menu;
    IBOutlet NSView*            _repeat_ContainerView;
    
    IBOutlet ContainerSubview*   _daySelector_View;
    IBOutlet NSSegmentedControl* _daySelector_Control;
    
    IBOutlet ContainerSubview*  _dateSelector_View;
    IBOutlet NSTokenField*      _dateSelector_Field;
    
    IBOutlet ContainerSubview*  _intervalSelector_View;
    IBOutlet NSTextField*       _intervalSelector_Field;
    IBOutlet NSTextField*       _intervalSelector_DescriptionLabel;
    
    // Capture
    IBOutlet NSTextField*        _capture_CountField;
    IBOutlet NSTextField*        _capture_IntervalLabel;
    IBOutlet NSTextField*        _capture_IntervalField;
    IBOutlet NSPopUpButton*      _capture_IntervalUnitMenu;
    IBOutlet NSSegmentedControl* _capture_FlashLEDsControl;
    
    // Constraints
    IBOutlet NSView*            _battery_ContainerView;
    
    IBOutlet ContainerSubview*  _battery_Motion_View;
    IBOutlet NSButton*          _battery_Motion_IgnoreTrigger_Checkbox;
    IBOutlet NSTextField*       _battery_Motion_IgnoreTrigger_DurationField;
    IBOutlet NSPopUpButton*     _battery_Motion_IgnoreTrigger_DurationUnitMenu;
    IBOutlet NSButton*          _battery_Motion_MaxTriggerCount_Checkbox;
    IBOutlet NSTextField*       _battery_Motion_MaxTriggerCount_Field;
    IBOutlet NSTextField*       _battery_Motion_MaxTriggerCount_Label;
    IBOutlet NSTextField*       _battery_Motion_MaxTriggerCount_DetailLabel;
    
//    CaptureTriggers _triggers;
    MSP::Triggers _triggers;
    std::vector<ListItem*> _items;
    bool _actionViewChangedUnderway;
}

//- (void)description {
//    Trigger triggers[32] = {};
//    size_t i = 0;
//    for (ListItem* it : _items) {
//        triggers[i] = it->trigger;
//        i++;
//    }
//    NSData* data = [NSData dataWithBytes:&triggers length:sizeof(triggers)];
//    [data writeToFile:@"/Users/dave/Desktop/test.bin" atomically:true];
//}

static void _SetEmptyMode(CaptureTriggersView* self, bool emptyMode) {
    [self->_noTriggersView setHidden:!emptyMode];
    [self->_addButton setHidden:emptyMode];
    [self->_removeButton setHidden:emptyMode];
    [self->_separatorLineOffset setConstant:(emptyMode ? 1000 : 8)];
}

static ListItem* _ListItemAdd(CaptureTriggersView* self, const CaptureTrigger& trigger) {
    assert(self);
    NSTableView* tv = self->_tableView;
    ListItem* it = [tv makeViewWithIdentifier:NSStringFromClass([ListItem class]) owner:nil];
    it->trigger = trigger;
    [it updateView];
    
    self->_items.push_back(it);
    const size_t idx = self->_items.size()-1;
    NSIndexSet* idxs = [NSIndexSet indexSetWithIndex:idx];
    [tv insertRowsAtIndexes:idxs withAnimation:NSTableViewAnimationEffectNone];
    [tv selectRowIndexes:idxs byExtendingSelection:false];
    [tv scrollRowToVisible:idx];
    
    _SetEmptyMode(self, false);
    return it;
}


//static ListItem* _ListItemAdd(CaptureTriggersView* self, CaptureTrigger::Type type) {
//    assert(self);
//    NSTableView* tv = self->_tableView;
//    ListItem* it = [tv makeViewWithIdentifier:NSStringFromClass([ListItem class]) owner:nil];
//    CaptureTrigger& t = it->trigger;
//    _TriggerInit(t, type);
//    [it updateView];
//    
//    self->_items.push_back(it);
//    const size_t idx = self->_items.size()-1;
//    NSIndexSet* idxs = [NSIndexSet indexSetWithIndex:idx];
//    [tv insertRowsAtIndexes:idxs withAnimation:NSTableViewAnimationEffectNone];
//    [tv selectRowIndexes:idxs byExtendingSelection:false];
//    [tv scrollRowToVisible:idx];
//    
//    _SetEmptyMode(self, false);
//    return it;
//}

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
    } else {
        _SetEmptyMode(self, true);
    }
}

// MARK: - Creation

//template<typename T>
//static void _Serialize(CaptureTriggers& x, T& d) {
//    CaptureTriggersSerialized s;
//    static_assert(sizeof(s) == sizeof(d));
//    memcpy(&s, d, sizeof(s));
//    x = Deserialize(s);
//}
//
//template<typename T>
//static void _Deserialize(CaptureTriggers& x, T& d) {
//    CaptureTriggersSerialized s;
//    static_assert(sizeof(s) == sizeof(d));
//    memcpy(&s, d, sizeof(s));
//    x = Deserialize(s);
//}

- (instancetype)initWithTriggers:(const MSP::Triggers&)triggers {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    _triggers = triggers;
    
    // Load view from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        NSView* nibView = self->_nibView;
        [nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:nibView];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(nibView)]];
    }
    
    [self->_tableView registerForDraggedTypes:@[_PboardDragItemsType]];
    [self->_tableView reloadData];
//    _ListItemAdd(self, CaptureTrigger::Type::Time);
//    _ListItemAdd(self, CaptureTrigger::Type::Motion);
//    _ListItemAdd(self, _TriggerMake(CaptureTrigger::Type::Button));
    
    [self->_dateSelector_Field setPlaceholderString:@(Calendar::DayOfYearPlaceholderString().c_str())];
    
    // Deserialize data
    CaptureTriggers t;
    Deserialize(t, triggers.source);
    for (auto it=std::begin(t.triggers); it!=std::begin(t.triggers)+t.count; it++) {
        _ListItemAdd(self, *it);
    }
    
    return self;
}

- (CaptureTriggers)_triggers {
    CaptureTriggers triggers;
    triggers.count = _items.size();
    size_t i = 0;
    for (ListItem* it : _items) {
        triggers.triggers[i] = it->trigger;
        i++;
    }
    return triggers;
}

template<typename T_Dst, typename T_Src>
T_Dst _Cast(const T_Src& x) {
    // Only support unsigned for now
    static_assert(!std::numeric_limits<T_Src>::is_signed);
    static_assert(!std::numeric_limits<T_Dst>::is_signed);
    const T_Dst DstMaxValue = std::numeric_limits<T_Dst>::max();
    if (x > DstMaxValue) {
        throw Toastbox::RuntimeError("value too large (value: %ju, max: %ju)", (uintmax_t)x, (uintmax_t)DstMaxValue);
    }
    return x;
}

static MSP::Capture _Convert(const Capture& x) {
    return MSP::Capture{
        .delayMs = MsForDuration(x.interval).count(),
        .count = x.count,
    };
}

static uint8_t _DaysOfWeekAdvance(uint8_t x, int dir) {
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

//static MSP::Triggers::Event::Type _Convert(CaptureTrigger::Type type) {
//    switch (type) {
//    CaptureTrigger::Type::Time:   return MSP::Triggers::Event::Type::TimeTrigger;
//    CaptureTrigger::Type::Motion: return MSP::Triggers::Event::Type::MotionEnable;
//    CaptureTrigger::Type::Button: return ;    
//    }
//    abort();
//}

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
static uint8_t _LeapYearPhase(const date::time_zone& tz, const date::local_seconds& tp) {
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
static date::local_seconds _PastTime(const T& now, Calendar::TimeOfDay timeOfDay) {
    const auto midnight = floor<date::days>(now);
    const auto t = midnight+timeOfDay;
    if (t < now) return t;
    return t-date::days(1);
}

static Time::Instant _TimeInstantForLocalTime(const date::time_zone& tz, const date::local_seconds& tp) {
    const auto tpUtc = date::clock_cast<date::utc_clock>(tz.to_sys(tp));
    const auto tpDevice = date::clock_cast<Time::Clock>(tpUtc);
    return Time::Clock::TimeInstantFromTimePoint(tpDevice);
}

static std::vector<MSP::Triggers::Event> _EventsCreate(MSP::Triggers::Event::Type type,
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
                .Daily = { _Cast<decltype(MSP::Repeat::Daily.interval)>(repeat->DayInterval.count()) },
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
Ms _MotionEnableDurationMs(const T& x) {
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
Ms _MotionSuppressMs(const T& x) {
    if (!x.constraints.suppressDuration.enable) {
        // Suppression feature disabled
        return {};
    }
    return MsForDuration(x.constraints.suppressDuration.duration);
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

static void _AddEvents(MSP::Triggers& triggers, const std::vector<MSP::Triggers::Event>& events) {
    const size_t eventsRem = std::size(triggers.event)-triggers.eventCount;
    if (events.size() > eventsRem) {
        throw Toastbox::RuntimeError("too many events");
    }
    std::copy(events.begin(), events.end(), triggers.event+triggers.eventCount);
    triggers.eventCount += events.size();
}

- (const MSP::Triggers&)triggers {
    CaptureTriggers triggers = [self _triggers];
    _triggers.eventCount = 0;
    _triggers.timeTriggerCount = 0;
    _triggers.motionTriggerCount = 0;
    _triggers.buttonTriggerCount = 0;
    
    for (size_t i=0; i<triggers.count; i++) {
        const CaptureTrigger& src = triggers.triggers[i];
        switch (src.type) {
        case CaptureTrigger::Type::Time: {
            // Make sure there's an available slot for the trigger
            if (_triggers.timeTriggerCount >= std::size(_triggers.timeTrigger)) {
                throw Toastbox::RuntimeError("no remaining time triggers");
            }
            
            const auto& x = src.time;
            
            // Create events for the trigger
            {
                const auto events = _EventsCreate(MSP::Triggers::Event::Type::TimeTrigger, x.schedule.time, &x.schedule.repeat, _triggers.timeTriggerCount);
                _AddEvents(_triggers, events);
            }
            
            // Create trigger
            {
                _triggers.timeTrigger[_triggers.timeTriggerCount] = {
                    .capture = _Convert(x.capture),
                };
                _triggers.timeTriggerCount++;
            }
            break;
        }
        
        case CaptureTrigger::Type::Motion: {
            // Make sure there's an available slot for the trigger
            if (_triggers.motionTriggerCount >= std::size(_triggers.motionTrigger)) {
                throw Toastbox::RuntimeError("no remaining motion triggers");
            }
            
            const auto& x = src.motion;
            
            // Create events for the trigger
            {
                const auto events = _EventsCreate(MSP::Triggers::Event::Type::MotionEnable, _MotionTimeOfDay(x), _MotionRepeat(x), _triggers.motionTriggerCount);
                _AddEvents(_triggers, events);
            }
            
            // Create trigger
            {
                const uint16_t count = (x.constraints.maxTriggerCount.enable ? x.constraints.maxTriggerCount.count : 0);
                const Ms durationMs = _MotionEnableDurationMs(x);
                const Ms suppressMs = _MotionSuppressMs(x);
                
                _triggers.motionTrigger[_triggers.motionTriggerCount] = {
                    .capture    = _Convert(x.capture),
                    .count      = count,
                    .durationMs = durationMs.count(),
                    .suppressMs = suppressMs.count(),
                };
                _triggers.motionTriggerCount++;
            }
            break;
        }
        
        case CaptureTrigger::Type::Button: {
            // Make sure there's an available slot for the trigger
            if (_triggers.buttonTriggerCount >= std::size(_triggers.buttonTrigger)) {
                throw Toastbox::RuntimeError("no remaining button triggers");
            }
            
            const auto& x = src.button;
            _triggers.buttonTrigger[_triggers.buttonTriggerCount] = {
                .capture = _Convert(x.capture),
            };
            _triggers.buttonTriggerCount++;
            break;
        }
        
        default: abort();
        }
    }
    
    Serialize(_triggers.source, triggers);
    return _triggers;
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
static void _Copy(Repeat::Type& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        std::string xstr = StringFromRepeatType(x);
        xstr[0] = std::toupper(xstr[0]);
        NSMenuItem* item = [menu itemWithTitle:@(xstr.c_str())];
        #warning TODO: is this a good behavior?
        if (!item) item = [menu itemAtIndex:0];
        [menu selectItem:item];
    
    } else {
        NSString* str = [menu titleOfSelectedItem];
        assert(str);
        x = RepeatTypeFromString([str UTF8String]);
    }
}

template<bool T_Forward>
static void _CopyTime(Calendar::TimeOfDay& x, NSTextField* field) {
    static constexpr Calendar::TimeOfDay Morning(12*60*60);
    if constexpr (T_Forward) {
        [field setStringValue:@(Calendar::StringFromTimeOfDay(x).c_str())];
    } else {
        try {
            const bool assumeAM = x < Morning;
            x = Calendar::TimeOfDayFromString([[field stringValue] UTF8String], assumeAM);
        } catch (...) {}
    }
}

template<bool T_Forward>
static void _Copy(uint16_t& x, NSTextField* field, uint16_t min=0) {
    if constexpr (T_Forward) {
        [field setStringValue:[NSString stringWithFormat:@"%ju",(uintmax_t)x]];
    } else {
        x = std::max((int)min, [field intValue]);
    }
}

template<bool T_Forward>
static void _Copy(DayInterval& x, NSTextField* field) {
    if constexpr (T_Forward) {
        [field setStringValue:[NSString stringWithFormat:@"%ju",(uintmax_t)x.count()]];
    } else {
        x = DayInterval(std::max(2, [field intValue]));
    }
}

template<bool T_Forward>
static void _Copy(DeviceSettings::Duration& x, NSTextField* field, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        [field setStringValue:@(_StringFromFloat(x.value).c_str())];
        [menu selectItemWithTitle:@(StringFromUnit(x.unit).c_str())];
    } else {
        const std::string xstr = [[menu titleOfSelectedItem] UTF8String];
        try {
            x.value = std::max(0.f, _FloatFromString([[field stringValue] UTF8String]));
        } catch (...) {}
        x.unit = UnitFromString([[menu titleOfSelectedItem] UTF8String]);
    }
}

static NSInteger _SegmentForDayOfWeek(Calendar::DayOfWeek x) {
    if (x == date::Monday)    return 0;
    if (x == date::Tuesday)   return 1;
    if (x == date::Wednesday) return 2;
    if (x == date::Thursday)  return 3;
    if (x == date::Friday)    return 4;
    if (x == date::Saturday)  return 5;
    if (x == date::Sunday)    return 6;
    abort();
}

//static Calendar::DayOfWeek _DayOfWeekFromSegment(NSInteger x) {
//    switch (x) {
//    case 0:  return date::Monday;
//    case 1:  return date::Tuesday;
//    case 2:  return date::Wednesday;
//    case 3:  return date::Thursday;
//    case 4:  return date::Friday;
//    case 5:  return date::Saturday;
//    case 6:  return date::Sunday;
//    default: abort();
//    }
//}

template<bool T_Forward>
static void _Copy(Calendar::DaysOfWeek& x, NSSegmentedControl* control) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        for (uint8_t i=0; i<7; i++) {
            const Calendar::DayOfWeek d = Calendar::DayOfWeek(i);
            [control setSelected:Calendar::DaysOfWeekGet(x, d) forSegment:_SegmentForDayOfWeek(d)];
        }
    } else {
        for (uint8_t i=0; i<7; i++) {
            const Calendar::DayOfWeek d = Calendar::DayOfWeek(i);
            Calendar::DaysOfWeekSet(x, d, [control isSelectedForSegment:_SegmentForDayOfWeek(d)]);
        }
    }
}

template<bool T_Forward>
static void _Copy(Calendar::DaysOfYear& x, NSTokenField* field) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        NSMutableArray* tokens = [NSMutableArray new];
        std::vector<Calendar::DayOfYear> days = VectorFromDaysOfYear(x);
        for (Calendar::DayOfYear day : days) {
            DayOfYearObj* x = [DayOfYearObj new];
            x->x = day;
            [tokens addObject:x];
        }
        [field setObjectValue:tokens];
    
    } else {
        NSArray* tokens = Toastbox::CastOrNull<NSArray*>([field objectValue]);
        std::vector<Calendar::DayOfYear> days;
        for (id t : tokens) {
            DayOfYearObj* x = Toastbox::CastOrNull<DayOfYearObj*>(t);
            if (!x) continue;
            days.push_back(x->x);
        }
        x = Calendar::DaysOfYearFromVector(days);
    }
}

template<bool T_Forward>
static void _Copy(LEDs& x, NSSegmentedControl* control) {
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
static void _Copy(Repeat& x, CaptureTriggersView* view, const char* menuLabel) {
    auto& v = *view;
    
    if (T_Forward) [v._repeat_MenuLabel setStringValue:@(menuLabel)];
    
    _Copy<T_Forward>(x.type, v._repeat_Menu);
    switch (x.type) {
    case Repeat::Type::Daily:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, nil);
        break;
    case Repeat::Type::DaysOfWeek:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, v._daySelector_View, v._repeat_Menu);
        _Copy<T_Forward>(x.DaysOfWeek, v._daySelector_Control);
        break;
    case Repeat::Type::DaysOfYear:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, v._dateSelector_View, v._repeat_Menu);
        _Copy<T_Forward>(x.DaysOfYear, v._dateSelector_Field);
        break;
    case Repeat::Type::DayInterval:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, v._intervalSelector_View, v._repeat_Menu);
        _Copy<T_Forward>(x.DayInterval, v._intervalSelector_Field);
        if constexpr (T_Forward) {
            [v._intervalSelector_DescriptionLabel setStringValue:@(("(" + _DayIntervalDetailedDescription(x.DayInterval) + ")").c_str())];
        }
        break;
    default:
        abort();
    }
}

template<bool T_Forward>
static void _CopyTimeRangeEnable(bool& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    if constexpr (T_Forward) {
        [menu selectItemAtIndex:(NSInteger)x];
    } else {
        x = (bool)[menu indexOfSelectedItem];
    }
}

template<bool T_Forward, typename T_TimeRange>
static void _CopyTimeRange(T_TimeRange& x, CaptureTriggersView* view) {
    auto& v = *view;
    _CopyTimeRangeEnable<T_Forward>(x.enable, v._schedule_Motion_TimeRange_Menu);
    _CopyTime<T_Forward>(x.start, v._schedule_Motion_TimeRange_TimeStartField);
    _CopyTime<T_Forward>(x.end, v._schedule_Motion_TimeRange_TimeEndField);
    if constexpr (T_Forward) {
        [v._schedule_Motion_TimeRange_TimeStartField setEnabled:x.enable];
        [v._schedule_Motion_TimeRange_TimeEndField setEnabled:x.enable];
    }
}

template<bool T_Forward>
static void _Copy(Capture& x, CaptureTriggersView* view) {
    auto& v = *view;
    _Copy<T_Forward>(x.count, v._capture_CountField);
    _Copy<T_Forward>(x.interval, v._capture_IntervalField, v._capture_IntervalUnitMenu);
    
    if constexpr (T_Forward) {
        [v._capture_IntervalLabel setEnabled:x.count>1];
        [v._capture_IntervalField setEnabled:x.count>1];
        [v._capture_IntervalUnitMenu setEnabled:x.count>1];
    }
    
    _Copy<T_Forward>(x.flashLEDs, v._capture_FlashLEDsControl);
}

template<bool T_Forward>
static void _Copy(CaptureTrigger& trigger, CaptureTriggersView* view) {
    auto& v = *view;
    switch (trigger.type) {
    case CaptureTrigger::Type::Time: {
        auto& x = trigger.time;
        
        // Schedule
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._schedule_ContainerView, v._schedule_Time_View);
            if constexpr (T_Forward) _ContainerSubviewSet(v._schedule_Time_RepeatContainerView, v._repeat_View, v._schedule_Time_TimeField);
            
            _CopyTime<T_Forward>(x.schedule.time, v._schedule_Time_TimeField);
            _Copy<T_Forward>(x.schedule.repeat, view, "Repeat:");
        }
        
        // Capture
        _Copy<T_Forward>(x.capture, view);
        
        // Constraints
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._battery_ContainerView, nil);
        }
        
        break;
    }
    
    case CaptureTrigger::Type::Motion: {
        auto& x = trigger.motion;
        
        // Schedule
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._schedule_ContainerView, nil);
            if constexpr (T_Forward) _ContainerSubviewSet(v._schedule_Motion_RepeatContainerView, v._repeat_View, v._schedule_Motion_TimeRange_Menu);
            
            _Copy<T_Forward>(x.schedule.repeat, view, "Active:");
            _CopyTimeRange<T_Forward>(x.schedule.timeRange, view);
        }
        
        // Capture
        _Copy<T_Forward>(x.capture, view);
        
        // Constraints
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._battery_ContainerView, v._battery_Motion_View);
            
            _Copy<T_Forward>(x.constraints.suppressDuration.enable, v._battery_Motion_IgnoreTrigger_Checkbox);
            _Copy<T_Forward>(x.constraints.suppressDuration.duration, v._battery_Motion_IgnoreTrigger_DurationField, v._battery_Motion_IgnoreTrigger_DurationUnitMenu);
            
            _Copy<T_Forward>(x.constraints.maxTriggerCount.enable, v._battery_Motion_MaxTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTriggerCount.count, v._battery_Motion_MaxTriggerCount_Field, 1);
            
            if constexpr (T_Forward) {
                if (!x.schedule.timeRange.enable) {
                    [v._battery_Motion_MaxTriggerCount_Label setStringValue:@"triggers, until next day"];
                    [v._battery_Motion_MaxTriggerCount_DetailLabel setHidden:true];
                
                } else {
                    [v._battery_Motion_MaxTriggerCount_Label setStringValue:@"triggers, until next time period"];
                    const std::string detail = "(" + _TimeRangeDescription(x.schedule.timeRange.start, x.schedule.timeRange.end) + ")";
                    [v._battery_Motion_MaxTriggerCount_DetailLabel setStringValue:@(detail.c_str())];
                    [v._battery_Motion_MaxTriggerCount_DetailLabel setHidden:false];
                }
            }
        }
        
        break;
    }
    
    case CaptureTrigger::Type::Button: {
        auto& x = trigger.button;
        
        // Schedule
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._schedule_ContainerView, nil);
        }
        
        // Capture
        _Copy<T_Forward>(x.capture, view);
        
        // Constraints
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._battery_ContainerView, nil);
        }
        
        break;
    }
    
    default:
        abort();
    }
}

// MARK: - Actions

- (ListItem*)_selectedItem {
    NSInteger idx = [_tableView selectedRow];
    if (idx < 0) return nil;
    return _items.at(idx);
}

static void _Store(CaptureTriggersView* self, CaptureTrigger& trigger) {
    _Copy<false>(trigger, self);
}

static void _Load(CaptureTriggersView* self, CaptureTrigger& trigger) {
    _Copy<true>(trigger, self);
    [[self window] recalculateKeyViewLoop];
}

static void _StoreLoad(CaptureTriggersView* self, bool initRepeat=false) {
    // Prevent re-entry, because our committing logic can trigger multiple calls
    if (self->_actionViewChangedUnderway) return;
    self->_actionViewChangedUnderway = true;
    Defer( self->_actionViewChangedUnderway = false );
    
    NSLog(@"_actionViewChanged");
    ListItem* it = [self _selectedItem];
    if (!it) return;
    CaptureTrigger& trigger = it->trigger;
    
    // Commit editing the active editor
    if (NSText* x = Toastbox::CastOrNull<NSText*>([[self window] firstResponder])) {
        // We call -insertNewline twice because NSTokenField has 2 sequential states
        // that the return key transitions through, and we want to transition through
        // both to get to the final "select all" state.
        [x insertNewline:nil];
        [x insertNewline:nil];
    }
    
    _Store(self, trigger);
    
    if (initRepeat) {
        switch (trigger.type) {
        case CaptureTrigger::Type::Time:   _TriggerInitRepeat(trigger.time.schedule.repeat); break;
        case CaptureTrigger::Type::Motion: _TriggerInitRepeat(trigger.motion.schedule.repeat); break;
        default:                    abort();
        }
    }
    
    _Load(self, trigger);
    [it updateView];
}

- (IBAction)_actionViewChanged:(id)sender {
    _StoreLoad(self);
}

- (IBAction)_actionRepeatMenuChanged:(id)sender {
    _StoreLoad(self, true);
}

- (IBAction)_actionAddTimeTrigger:(id)sender {
    _ListItemAdd(self, _TriggerMake(CaptureTrigger::Type::Time));
}

- (IBAction)_actionAddMotionTrigger:(id)sender {
    _ListItemAdd(self, _TriggerMake(CaptureTrigger::Type::Motion));
}

- (IBAction)_actionAddButtonTrigger:(id)sender {
    _ListItemAdd(self, _TriggerMake(CaptureTrigger::Type::Button));
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
    ListItem* it = (idx>=0 ? _items.at(idx) : nil);
    
    _ContainerSubviewSet(_containerView, (it ? _detailView : nil));
    [_removeButton setEnabled:(bool)it];
    if (!it) return;
    _Load(self, it->trigger);
}












- (NSArray*)tokenField:(NSTokenField*)field shouldAddObjects:(NSArray*)tokens atIndex:(NSUInteger)index {
    if (field != _dateSelector_Field) abort();
    
    NSLog(@"_dateSelector_Field");
    NSMutableArray* filtered = [NSMutableArray new];
    for (NSString* x : tokens) {
        auto day = Calendar::DayOfYearFromString([x UTF8String]);
        if (!day) continue;
        DayOfYearObj* obj = [DayOfYearObj new];
        obj->x = *day;
        [filtered addObject:obj];
    }
    return filtered;
}

- (NSString*)tokenField:(NSTokenField*)field displayStringForRepresentedObject:(id)obj {
    if (field != _dateSelector_Field) abort();
    
    if (DayOfYearObj* x = Toastbox::CastOrNull<DayOfYearObj*>(obj)) {
        return @(Calendar::StringFromDayOfYear(x->x).c_str());
    }
    return obj;
}

// MARK: - Table View Drag / Drop

static NSString*const _PboardDragItemsType = @"com.heytoaster.mdcstudio.CaptureTriggersView.PasteboardType";

- (id<NSPasteboardWriting>)tableView:(NSTableView*)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem* pb = [NSPasteboardItem new];
    [pb setPropertyList:@(row) forType:_PboardDragItemsType];
    return pb;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info
    proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)drop {
    
    if (drop == NSTableViewDropAbove) return NSDragOperationMove;
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id<NSDraggingInfo>)info
    row:(NSInteger)row dropOperation:(NSTableViewDropOperation)drop {
    
    NSArray<NSPasteboardItem*>* items = [[info draggingPasteboard] pasteboardItems];
    
    std::set<size_t> rows;
    std::vector<ListItem*> movedItems;
    NSMutableIndexSet* idxsOld = [NSMutableIndexSet new];
    size_t dstIdx = row;
    NSIndexSet* selection = [_tableView selectedRowIndexes];
    bool reselect = false;
    
    // Compose `movedItems`
    for (NSPasteboardItem* it : items) {
        NSNumber* num = Toastbox::Cast<NSNumber*>([it propertyListForType:_PboardDragItemsType]);
        const size_t idx = (size_t)[num unsignedIntegerValue];
        rows.insert(idx);
        [idxsOld addIndex:idx];
        movedItems.push_back(_items[idx]);
        reselect |= [selection containsIndex:idx];
        if (idx < dstIdx) {
            dstIdx--;
        }
    }
    
    NSIndexSet* idxsNew = [NSIndexSet indexSetWithIndexesInRange:{dstIdx, movedItems.size()}];
    
    // Remove moved items
    {
        size_t off = 0;
        for (size_t row : rows) {
            _items.erase(_items.begin() + row - off);
            off++;
        }
        [_tableView removeRowsAtIndexes:idxsOld withAnimation:NSTableViewAnimationEffectNone];
    }
    
    // Add moved items
    {
        _items.insert(_items.begin()+dstIdx, movedItems.begin(), movedItems.end());
        [_tableView insertRowsAtIndexes:idxsNew withAnimation:NSTableViewAnimationEffectNone];
        // Select new rows, if the dragged items were originally selected
        if (reselect) {
            [_tableView selectRowIndexes:idxsNew byExtendingSelection:false];
            [_tableView scrollRowToVisible:dstIdx];
        }
    }
    
    return true;
}

- (NSView*)deviceSettingsView_HeaderEndView {
    return _separatorLine;
}

//- (NSLayoutYAxisAnchor*)deviceSettingsView_HeaderBottomAnchor {
//    return [_containerView topAnchor];
//}
//
//- (CGFloat)deviceSettingsView_HeaderBottomAnchorOffset {
//    if ([_detailView superview]) {
//        return 8;
//    }
//    return 0;
//}

@end

//@interface RedView : NSView
//@end
//
//@implementation RedView
//
////- (void)drawRect:(NSRect)rect {
////    [[NSColor redColor] set];
////    NSRectFill(rect);
////}
//
//@end
