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
    
    struct [[gnu::packed]] Repeat {
        enum class Type : uint8_t {
            Daily,
            WeekDays,
            YearDays,
            Interval,
        };
        
        Type type;
        union {
            Calendar::WeekDays weekDays;
            Calendar::YearDays yearDays;
            uint32_t interval;
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
        
        uint32_t value;
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
                
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t count;
                } maxTotalTriggerCount;
            } constraints;
        } motion;
        
        struct [[gnu::packed]] {
            Capture capture;
            
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    uint32_t count;
                } maxTotalTriggerCount;
            } constraints;
        } button;
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

static const Calendar::YearDays _YearDaysInit = Calendar::YearDaysFromVector({Calendar::YearDay{9,20}, Calendar::YearDay{12,31}});

static constexpr uint32_t _IntervalInit = 2;

//static Trigger::Repeat& _TriggerRepeatGet(Trigger& t) {
//    switch (t.type) {
//    case Trigger::Type::Time:   return t.time.schedule.repeat;
//    case Trigger::Type::Motion: return t.motion.schedule.repeat;
//    default:                    abort();
//    }
//}

static void _InitTriggerRepeat(Trigger::Repeat& x) {
    using X = Trigger::Repeat::Type;
    switch (x.type) {
    case X::Daily:
        break;
    case X::WeekDays:
        x.weekDays = _WeekDaysInit;
        break;
    case X::YearDays:
        x.yearDays = _YearDaysInit;
        break;
    case X::Interval:
        x.interval = _IntervalInit;
        break;
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
            .repeat = {
                .type = Trigger::Repeat::Type::Daily,
            },
        };
        
        x.capture = {
            .count = 1,
            .interval = Trigger::Duration{
                .value = 0,
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
        auto& x = t.motion;
        
        x.schedule = {
            .timeRange = {
                .enable = false,
                .start = _TimeStartInit,
                .end = _TimeEndInit,
            },
            .repeat = {
                .type = Trigger::Repeat::Type::Daily,
            },
        };
        
        x.capture = {
            .count = 1,
            .interval = Trigger::Duration{
                .value = 0,
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
        auto& x = t.button;
        
        x.capture = {
            .count = 1,
            .interval = Trigger::Duration{
                .value = 0,
                .unit = Trigger::Duration::Unit::Seconds,
            },
            .flashLEDs = Trigger::LEDs::None,
        };
        
        x.constraints = {
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

static std::string StringFromRepeatType(const Trigger::Repeat::Type& x) {
    using X = std::remove_reference_t<decltype(x)>;
    switch (x) {
    case X::Daily:      return "every day";
    case X::WeekDays:   return "on days";
    case X::YearDays:   return "on dates";
    case X::Interval:   return "on interval";
    default:            abort();
    }
}

static Trigger::Repeat::Type RepeatTypeFromString(std::string x) {
    using X = Trigger::Repeat::Type;
    for (auto& c : x) c = std::tolower(c);
         if (x == "every day")     return X::Daily;
    else if (x == "on days")       return X::WeekDays;
    else if (x == "on dates")      return X::YearDays;
    else if (x == "on interval")   return X::Interval;
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

static std::string _WeekDaysDescription(const Calendar::WeekDays& x) {
    using X = Calendar::WeekDays;
    // Only one day set
    switch (x) {
    case X::Mon:  return "mondays";
    case X::Tue:  return "tuesdays";
    case X::Wed:  return "wednesdays";
    case X::Thu:  return "thursdays";
    case X::Fri:  return "fridays";
    case X::Sat:  return "saturdays";
    case X::Sun:  return "sundays";
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

static std::string _YearDaysDescription(const Calendar::YearDays& x) {
    const size_t count = VectorFromYearDays(x).size();
    if (count == 1) return "1 day per year";
    return std::to_string(count) + " days per year";
}

static std::string _IntervalDescription(uint32_t x) {
    if (x == 0) return "every day";
    if (x == 1) return "every day";
    if (x == 2) return "every other day";
    return "every " + std::to_string(x) + " days";
}

static std::string _IntervalDetailedDescription(uint32_t x) {
    if (x == 0) return "every day";
    if (x == 1) return "every day";
    if (x == 2) return "every other day";
    return "1 day on, " + std::to_string(x-1) + " days off";
}

static std::string _Capitalize(std::string x) {
    if (!x.empty()) {
        x[0] = std::toupper(x[0]);
    }
    return x;
}

static std::string _RepeatDescription(const Trigger::Repeat& x) {
    using T = Trigger::Repeat::Type;
    std::string s;
    switch (x.type) {
    case T::Daily:    return "daily";
    case T::WeekDays: return _WeekDaysDescription(x.weekDays);
    case T::YearDays: return _YearDaysDescription(x.yearDays);
    case T::Interval: return _IntervalDescription(x.interval);
    default:          abort();
    }
}

static std::string _CaptureDescription(const Trigger::Capture& x) {
    std::string str = "capture " + std::to_string(x.count) + " image" + (x.count!=1 ? "s" : "");
    if (x.count>1 && x.interval.value) {
        str += " (" + std::to_string(x.interval.value) + _SuffixForDurationUnit(x.interval.unit) + " interval)";
    }
    return str;
}

static std::string _TimeRangeDescription(uint32_t start, uint32_t end) {
    std::string r;
    r += _TimeOfDayStringFromSeconds(start);
    r += " – ";
    r += _TimeOfDayStringFromSeconds(end);
    return r;
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
        subtitle = _Capitalize(_RepeatDescription(x.schedule.repeat));
        break;
    }
    
    case Trigger::Type::Motion: {
        auto& x = trigger.motion;
        auto& repeat = trigger.motion.schedule.repeat;
        if (repeat.type != Trigger::Repeat::Type::Daily) {
            subtitle = _Capitalize(_RepeatDescription(repeat));
        }
        
        if (x.schedule.timeRange.enable) {
            if (!subtitle.empty()) subtitle += ", ";
            subtitle += _TimeRangeDescription(x.schedule.timeRange.start, x.schedule.timeRange.end);
        }
        break;
    }
    
    case Trigger::Type::Button: {
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
    case Trigger::Type::Time: {
        auto& x = trigger.time;
        [_descriptionLabel setStringValue:@(_CaptureDescription(x.capture).c_str())];
        break;
    }
    
    case Trigger::Type::Motion: {
        auto& x = trigger.motion;
        [_descriptionLabel setStringValue:@(_CaptureDescription(x.capture).c_str())];
        break;
    }
    
    case Trigger::Type::Button: {
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
    IBOutlet NSView* _nibView;
    
    IBOutlet NSTableView* _tableView;
    IBOutlet NSView* _containerView;
    IBOutlet ContainerSubview* _detailView;
    IBOutlet ContainerSubview* _noSelectionView;
    
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
    IBOutlet NSButton*          _battery_Motion_MaxTotalTriggerCount_Checkbox;
    IBOutlet NSTextField*       _battery_Motion_MaxTotalTriggerCount_Field;
    
    IBOutlet ContainerSubview*  _battery_TimeButton_View;
    IBOutlet NSButton*          _battery_TimeButton_MaxTotalTriggerCount_Checkbox;
    IBOutlet NSTextField*       _battery_TimeButton_MaxTotalTriggerCount_Field;
    
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
    const size_t idx = self->_items.size()-1;
    NSIndexSet* idxs = [NSIndexSet indexSetWithIndex:idx];
    [tv insertRowsAtIndexes:idxs withAnimation:NSTableViewAnimationEffectNone];
    [tv selectRowIndexes:idxs byExtendingSelection:false];
    [tv scrollRowToVisible:idx];
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
    
    [self->_dateSelector_Field setPlaceholderString:@(Calendar::YearDayPlaceholderString().c_str())];
    
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
static void _Copy(Trigger::Repeat::Type& x, NSPopUpButton* menu) {
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
static void _Copy(Trigger::Repeat& x, CaptureTriggersView* view, const char* menuLabel) {
    auto& v = *view;
    
    if (T_Forward) [v._repeat_MenuLabel setStringValue:@(menuLabel)];
    
    _Copy<T_Forward>(x.type, v._repeat_Menu);
    switch (x.type) {
    case Trigger::Repeat::Type::Daily:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, nil);
        break;
    case Trigger::Repeat::Type::WeekDays:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, v._daySelector_View, v._repeat_Menu);
        _Copy<T_Forward>(x.weekDays, v._daySelector_Control);
        break;
    case Trigger::Repeat::Type::YearDays:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, v._dateSelector_View, v._repeat_Menu);
        _Copy<T_Forward>(x.yearDays, v._dateSelector_Field);
        break;
    case Trigger::Repeat::Type::Interval:
        if constexpr (T_Forward) _ContainerSubviewSet(v._repeat_ContainerView, v._intervalSelector_View, v._repeat_Menu);
        _Copy<T_Forward>(x.interval, v._intervalSelector_Field);
        if constexpr (T_Forward) {
            [v._intervalSelector_DescriptionLabel setStringValue:@(("(" + _IntervalDetailedDescription(x.interval) + ")").c_str())];
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
static void _Copy(Trigger::Capture& x, CaptureTriggersView* view) {
    auto& v = *view;
    _Copy<T_Forward>(x.count, v._capture_CountField);
    _Copy<T_Forward>(x.interval.value, v._capture_IntervalField);
    _Copy<T_Forward>(x.interval.unit, v._capture_IntervalUnitMenu);
    
    if constexpr (T_Forward) {
        [v._capture_IntervalLabel setEnabled:x.count>1];
        [v._capture_IntervalField setEnabled:x.count>1];
        [v._capture_IntervalUnitMenu setEnabled:x.count>1];
    }
    
    _Copy<T_Forward>(x.flashLEDs, v._capture_FlashLEDsControl);
}

template<bool T_Forward>
static void _Copy(Trigger& trigger, CaptureTriggersView* view) {
    auto& v = *view;
    switch (trigger.type) {
    case Trigger::Type::Time: {
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
            if constexpr (T_Forward) _ContainerSubviewSet(v._battery_ContainerView, v._battery_TimeButton_View);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.enable, v._battery_TimeButton_MaxTotalTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.count, v._battery_TimeButton_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    case Trigger::Type::Motion: {
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
            
            _Copy<T_Forward>(x.constraints.ignoreTriggerDuration.enable, v._battery_Motion_IgnoreTrigger_Checkbox);
            _Copy<T_Forward>(x.constraints.ignoreTriggerDuration.duration.value, v._battery_Motion_IgnoreTrigger_DurationField);
            _Copy<T_Forward>(x.constraints.ignoreTriggerDuration.duration.unit, v._battery_Motion_IgnoreTrigger_DurationUnitMenu);
            
            _Copy<T_Forward>(x.constraints.maxTriggerCount.enable, v._battery_Motion_MaxTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTriggerCount.count, v._battery_Motion_MaxTriggerCount_Field);
            
            if constexpr (T_Forward) {
                if (!x.schedule.timeRange.enable) {
                    [v._battery_Motion_MaxTriggerCount_Label setStringValue:@"triggers per day"];
                    [v._battery_Motion_MaxTriggerCount_DetailLabel setHidden:true];
                
                } else {
                    [v._battery_Motion_MaxTriggerCount_Label setStringValue:@"triggers per time period"];
                    const std::string detail = "(" + _TimeRangeDescription(x.schedule.timeRange.start, x.schedule.timeRange.end) + ")";
                    [v._battery_Motion_MaxTriggerCount_DetailLabel setStringValue:@(detail.c_str())];
                    [v._battery_Motion_MaxTriggerCount_DetailLabel setHidden:false];
                }
            }
            
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.enable, v._battery_Motion_MaxTotalTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.count, v._battery_Motion_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    case Trigger::Type::Button: {
        auto& x = trigger.button;
        
        // Schedule
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._schedule_ContainerView, nil);
        }
        
        // Capture
        _Copy<T_Forward>(x.capture, view);
        
        // Constraints
        {
            if constexpr (T_Forward) _ContainerSubviewSet(v._battery_ContainerView, v._battery_TimeButton_View);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.enable, v._battery_TimeButton_MaxTotalTriggerCount_Checkbox);
            _Copy<T_Forward>(x.constraints.maxTotalTriggerCount.count, v._battery_TimeButton_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    default:
        abort();
    }
}


//- (void)_storeViewToModel:(Trigger&)trigger {
////    if (NSText* x = Toastbox::CastOrNull<NSText*>([[self window] firstResponder])) {
////        [x selectAll:nil];
////    }
////    [[[self window] firstResponder] insertNewline:nil];
////    NSLog(@"%@", [[[self window] firstResponder] insertNewline:nil]);
////    [[self window] firstResponder];
////    [[self window] endEditingFor:nil];
////    [[self window] firstResponder] endEditing;
//    _Copy<false>(trigger, self);
//}

//- (void)_loadViewFromModel:(Trigger&)trigger {
//    _Copy<true>(trigger, self);
//    [[self window] recalculateKeyViewLoop];
//}





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






// MARK: - Actions

- (ListItem*)_selectedItem {
    NSInteger idx = [_tableView selectedRow];
    if (idx < 0) return nil;
    return _items.at(idx);
}

static void _Store(CaptureTriggersView* self, Trigger& trigger) {
    _Copy<false>(trigger, self);
}

static void _Load(CaptureTriggersView* self, Trigger& trigger) {
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
    Trigger& trigger = it->trigger;
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
    
    _Store(self, trigger);
    
    if (initRepeat) {
        switch (trigger.type) {
        case Trigger::Type::Time:   _InitTriggerRepeat(trigger.time.schedule.repeat); break;
        case Trigger::Type::Motion: _InitTriggerRepeat(trigger.motion.schedule.repeat); break;
        default:                    abort();
        }
    }
    
    _Load(self, trigger);
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

- (IBAction)_actionRepeatMenuChanged:(id)sender {
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

- (IBAction)_actionDismiss:(id)sender {
    [[[self window] sheetParent] endSheet:[self window]];
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
    
    [_noSelectionView setHidden:(bool)it];
    [_detailView setHidden:!it];
    if (!it) return;
    _Load(self, it->trigger);
}












- (NSArray*)tokenField:(NSTokenField*)field shouldAddObjects:(NSArray*)tokens atIndex:(NSUInteger)index {
//    NSLog(@"%@", NSStringFromSelector(_cmd));
//    return nil;
    
    if (field != _dateSelector_Field) abort();
    
    NSLog(@"_dateSelector_Field");
    NSMutableArray* filtered = [NSMutableArray new];
    for (NSString* x : tokens) {
        auto day = Calendar::YearDayFromString([x UTF8String]);
        if (!day) continue;
        YearDayObj* obj = [YearDayObj new];
        obj->x = *day;
        [filtered addObject:obj];
    }
    return filtered;
}

- (NSString*)tokenField:(NSTokenField*)field displayStringForRepresentedObject:(id)obj {
    if (field != _dateSelector_Field) abort();
    
    if (YearDayObj* x = Toastbox::CastOrNull<YearDayObj*>(obj)) {
        return @(Calendar::StringFromYearDay(x->x).c_str());
    }
    return obj;
}

@end
