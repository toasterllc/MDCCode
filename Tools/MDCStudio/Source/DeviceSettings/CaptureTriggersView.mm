#import "CaptureTriggersView.h"
#import <vector>
#import "Toastbox/Mac/Util.h"
#import "Toastbox/RuntimeError.h"

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
    
    enum class MonthDays : uint32_t {};
    
    using YearDays = MonthDays[12];
    
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
                    WeekDays weekDays;
                    MonthDays monthDays;
                    YearDays yearDays;
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
                        WeekDays weekDays;
                        MonthDays monthDays;
                        YearDays yearDays;
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

struct [[gnu::packed]] Triggers {
    Trigger triggers[32];
    uint8_t triggersCount = 0;
};


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
        [x.dateFormatterHH setTimeZone:[x.calendar timeZone]];
        [x.dateFormatterHH setLocalizedDateFormatFromTemplate:@"hh"];
        [x.dateFormatterHH setLenient:true];
    }
    
    {
        x.dateFormatterHHMM = [[NSDateFormatter alloc] init];
        [x.dateFormatterHHMM setLocale:[NSLocale autoupdatingCurrentLocale]];
        [x.dateFormatterHHMM setTimeZone:[x.calendar timeZone]];
        [x.dateFormatterHHMM setLocalizedDateFormatFromTemplate:@"hh:mm"];
        [x.dateFormatterHHMM setLenient:true];
    }
    
    {
        x.dateFormatterHHMMSS = [[NSDateFormatter alloc] init];
        [x.dateFormatterHHMMSS setLocale:[NSLocale autoupdatingCurrentLocale]];
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

static std::string _StringForWeekDays(const Trigger::WeekDays& x) {
    using X = Trigger::WeekDays;
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

static std::string _StringForMonthDays(const Trigger::MonthDays& x) {
    size_t count = 0;
    auto y = std::to_underlying(x);
    while (y) {
        count += y&1;
        y >>= 1;
    }
    return std::to_string(count) + " days per month";
}

static std::string _StringForYearDays(const Trigger::YearDays& x) {
    size_t count = 0;
    for (auto y : x) {
        auto z = std::to_underlying(y);
        while (z) {
            count += z&1;
            z >>= 1;
        }
    }
    return std::to_string(count) + " days per year";
}

template<typename T>
static std::string _DescriptionString(const T& x) {
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
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Time"]];
        [_titleLabel setStringValue: @(("At " + _TimeOfDayStringFromSeconds(trigger.time.schedule.time)).c_str())];
        break;
    case Trigger::Type::Motion:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Motion"]];
        [_titleLabel setStringValue:@"On motion"];
        break;
    case Trigger::Type::Button:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Button"]];
        [_titleLabel setStringValue:@"On button press"];
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
        case Trigger::Cadence::Weekly:  subtitle = _StringForWeekDays(x.schedule.weekDays); break;
        case Trigger::Cadence::Monthly: subtitle = _StringForMonthDays(x.schedule.monthDays); break;
        case Trigger::Cadence::Yearly:  subtitle = _StringForYearDays(x.schedule.yearDays); break;
        default:                        abort();
        }
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = trigger.motionButton;
        
        if (x.schedule.dayLimit.enable) {
            switch (x.schedule.dayLimit.cadence) {
            case Trigger::Cadence::Weekly:  subtitle = _StringForWeekDays(x.schedule.dayLimit.weekDays); break;
            case Trigger::Cadence::Monthly: subtitle = _StringForMonthDays(x.schedule.dayLimit.monthDays); break;
            case Trigger::Cadence::Yearly:  subtitle = _StringForYearDays(x.schedule.dayLimit.yearDays); break;
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
        [_descriptionLabel setStringValue:@(_DescriptionString(x.capture).c_str())];
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = trigger.motionButton;
        [_descriptionLabel setStringValue:@(_DescriptionString(x.capture).c_str())];
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
    IBOutlet NSTextField*       _monthDaySelector_Field;
    
    IBOutlet ContainerSubview*  _yearDaySelector_View;
    IBOutlet NSTextField*       _yearDaySelector_Field;
    
    // Capture
    IBOutlet NSTextField*        _capture_CountField;
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
}

static ListItem* _ListItemCreate(NSTableView* v) {
    assert(v);
    return [v makeViewWithIdentifier:NSStringFromClass([ListItem class]) owner:nil];
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
    
    {
        ListItem* item = _ListItemCreate(self->_tableView);
        Trigger& t = item->trigger;
        t.type = Trigger::Type::Time;
        [item updateView];
        self->_items.push_back(item);
    }
    
    {
        ListItem* item = _ListItemCreate(self->_tableView);
        Trigger& t = item->trigger;
        t.type = Trigger::Type::Motion;
        [item updateView];
        self->_items.push_back(item);
    }
    
    {
        ListItem* item = _ListItemCreate(self->_tableView);
        Trigger& t = item->trigger;
        t.type = Trigger::Type::Button;
        [item updateView];
        self->_items.push_back(item);
    }
    
    [self->_tableView reloadData];
    
//    [self _loadViewFromModel:self->_triggers.triggers[0]];
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

static void _SetContainerSubview(NSView* container, ContainerSubview* subview, NSView* alignView=nil) {
    // Either subview==nil, or existence of `alignView` matches existence of `subview->alignView`
    assert(!subview || ((bool)alignView == (bool)subview->alignView));
    
    [subview removeFromSuperview];
    [container setSubviews:@[]];
    if (!subview) return;
    
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
static void _Copy(Trigger::WeekDays& x, NSSegmentedControl* control) {
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
static void _Copy(Trigger::MonthDays& x, NSTextField* field) {
    using X = std::remove_reference_t<decltype(x)>;
    #warning TODO: implement
}

template<bool T_Forward>
static void _Copy(Trigger::YearDays& x, NSTextField* field) {
    using X = std::remove_reference_t<decltype(x)>;
    #warning TODO: implement
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
            if constexpr (T_Forward) _SetContainerSubview(y._schedule_ContainerView, y._schedule_Time_View);
            
            _CopyTime<T_Forward>(x.schedule.time, y._schedule_Time_TimeField);
            _Copy<T_Forward>(x.schedule.cadence, y._schedule_Time_CadenceMenu);
            switch (x.schedule.cadence) {
            case Trigger::Cadence::Daily:
                if constexpr (T_Forward) _SetContainerSubview(y._schedule_Time_DaySelectorContainerView, nil);
                break;
            case Trigger::Cadence::Weekly:
                if constexpr (T_Forward) _SetContainerSubview(y._schedule_Time_DaySelectorContainerView, y._weekDaySelector_View, y._schedule_Time_CadenceMenu);
                _Copy<T_Forward>(x.schedule.weekDays, y._weekDaySelector_Control);
                break;
            case Trigger::Cadence::Monthly:
                if constexpr (T_Forward) _SetContainerSubview(y._schedule_Time_DaySelectorContainerView, y._monthDaySelector_View, y._schedule_Time_CadenceMenu);
                _Copy<T_Forward>(x.schedule.monthDays, y._monthDaySelector_Field);
                break;
            case Trigger::Cadence::Yearly:
                if constexpr (T_Forward) _SetContainerSubview(y._schedule_Time_DaySelectorContainerView, y._yearDaySelector_View, y._schedule_Time_CadenceMenu);
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
            _Copy<T_Forward>(x.capture.flashLEDs, y._capture_FlashLEDsControl);
        }
        
        // Limits
        {
            if constexpr (T_Forward) _SetContainerSubview(y._constraints_ContainerView, nil);
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
            if constexpr (T_Forward) _SetContainerSubview(y._schedule_ContainerView, y._schedule_Motion_View);
            
            _Copy<T_Forward>(x.schedule.timeLimit.enable, y._schedule_Motion_LimitTime_Checkbox);
            _CopyTime<T_Forward>(x.schedule.timeLimit.start, y._schedule_Motion_LimitTime_TimeStartField);
            _CopyTime<T_Forward>(x.schedule.timeLimit.end, y._schedule_Motion_LimitTime_TimeEndField);
            _Copy<T_Forward>(x.schedule.dayLimit.enable, y._schedule_Motion_LimitDays_Checkbox);
            _Copy<T_Forward>(x.schedule.dayLimit.cadence, y._schedule_Motion_LimitDays_CadenceMenu);
            
            switch (x.schedule.dayLimit.cadence) {
            case Trigger::Cadence::Daily:
            case Trigger::Cadence::Weekly:
                if constexpr (T_Forward) _SetContainerSubview(y._schedule_Motion_DaySelectorContainerView, y._weekDaySelector_View, y._schedule_Motion_LimitTime_TimeStartField);
                _Copy<T_Forward>(x.schedule.dayLimit.weekDays, y._weekDaySelector_Control);
                break;
            case Trigger::Cadence::Monthly:
                if constexpr (T_Forward) _SetContainerSubview(y._schedule_Motion_DaySelectorContainerView, y._monthDaySelector_View, y._schedule_Motion_LimitTime_TimeStartField);
                _Copy<T_Forward>(x.schedule.dayLimit.monthDays, y._monthDaySelector_Field);
                break;
            case Trigger::Cadence::Yearly:
                if constexpr (T_Forward) _SetContainerSubview(y._schedule_Motion_DaySelectorContainerView, y._yearDaySelector_View, y._schedule_Motion_LimitTime_TimeStartField);
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
            _Copy<T_Forward>(x.capture.flashLEDs, y._capture_FlashLEDsControl);
        }
        
        // Limits
        {
            if constexpr (T_Forward) _SetContainerSubview(y._constraints_ContainerView, y._constraints_Motion_View, y._constraints_MaxTotalTriggerCount_Field);
            
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

- (void)_loadViewFromModel:(Trigger&)trigger {
    _Copy<true>(trigger, self);
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








//static void _MonthDaysLoad(const Trigger::MonthDays& days, NSSegmentedControl* control) {
//    using D = Trigger::WeekDays_;
//    size_t idx = 0;
//    for (Trigger::WeekDays day : { D::Mon, D::Tue, D::Wed, D::Thu, D::Fri, D::Sat, D::Sun }) {
//        [control setSelected:(days & day) forSegment:idx];
//        idx++;
//    }
//}
//
//static void _MonthDaysStore(Trigger::MonthDays& days, NSSegmentedControl* control) {
//    using D = Trigger::WeekDays_;
//    size_t idx = 0;
//    for (Trigger::WeekDays day : { D::Mon, D::Tue, D::Wed, D::Thu, D::Fri, D::Sat, D::Sun }) {
//        days |= ([control isSelectedForSegment:idx] ? day : 0);
//        idx++;
//    }
//}

- (void)_storeViewToModel:(Trigger&)trigger {
    _Copy<false>(trigger, self);
}

// MARK: - Actions

- (ListItem*)_selectedItem {
    NSInteger idx = [_tableView selectedRow];
    if (idx < 0) return nil;
    return _items.at(idx);
}

- (IBAction)_viewChangedAction:(id)sender {
    ListItem* item = [self _selectedItem];
    if (!item) return;
    [self _storeViewToModel:item->trigger];
    [self _loadViewFromModel:item->trigger];
    [item updateView];
}

- (IBAction)_action_cadence:(id)sender {
    
}

- (IBAction)_action_captureCount:(id)sender {
    
}

- (IBAction)_action_captureInterval:(id)sender {
    
}

- (IBAction)_action_flashLED:(id)sender {
    
}

- (IBAction)_action_maxTriggerCount:(id)sender {
    
}

- (IBAction)_action_maxTotalTriggerCount:(id)sender {
    
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
    if (idx < 0) return;
    ListItem* item = _items.at(idx);
    
    [self _loadViewFromModel:item->trigger];
    
//    item->trigger;
//    
//    NSLog(@"tableViewSelectionDidChange");
}

@end
