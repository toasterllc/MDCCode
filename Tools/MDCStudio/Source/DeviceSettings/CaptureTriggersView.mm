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
    
    enum class MonthDays : uint8_t {};
    
    using YearDays = uint32_t[12];
    
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
static NSString* _TimeOfDayStringFromSeconds(uint32_t x, bool full=false) {
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
    
    if (full) return [_TimeFormatStateGet().dateFormatterHHMMSS stringFromDate:date];
    
    if (!s && !m) {
        return [_TimeFormatStateGet().dateFormatterHH stringFromDate:date];
    } else if (!s) {
        return [_TimeFormatStateGet().dateFormatterHHMM stringFromDate:date];
    } else {
        return [_TimeFormatStateGet().dateFormatterHHMMSS stringFromDate:date];
    }
}

// 3:46:29 PM / 15:46:29 -> 56789
static uint32_t _SecondsFromTimeOfDayString(NSString* x) {
    NSDate* date = [_TimeFormatStateGet().dateFormatterHHMMSS dateFromString:x];
    if (!date) date = [_TimeFormatStateGet().dateFormatterHHMM dateFromString:x];
    if (!date) date = [_TimeFormatStateGet().dateFormatterHH dateFromString:x];
    if (!date) throw Toastbox::RuntimeError("invalid time of day: %s", [x UTF8String]);
    
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

static NSString* _WeeklyString(const Trigger::WeekDays& x) {
    using X = Trigger::WeekDays;
    // Only one day set
    switch (x) {
    case X::None: return @"Never";
    case X::Mon:  return @"Mondays";
    case X::Tue:  return @"Tuesdays";
    case X::Wed:  return @"Wednesdays";
    case X::Thu:  return @"Thursdays";
    case X::Fri:  return @"Fridays";
    case X::Sat:  return @"Saturdays";
    case X::Sun:  return @"Sundays";
    }
    
    constexpr auto MF = (X)(std::to_underlying(X::Mon) |
                            std::to_underlying(X::Tue) |
                            std::to_underlying(X::Wed) |
                            std::to_underlying(X::Thu) |
                            std::to_underlying(X::Fri));
    if (x == MF) return @"Mon-Fri";
    
    static const char* Names[] = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    
    NSMutableString* r = [NSMutableString new];
    size_t i = 0;
    size_t count = 0;
    bool first = true;
    for (auto y : { X::Mon, X::Tue, X::Wed, X::Thu, X::Fri, X::Sat, X::Sun }) {
        if (std::to_underlying(x) & std::to_underlying(y)) {
            if (!first) [r appendString:@", "];
            [r appendFormat:@"%s", Names[i]];
            first = false;
            count++;
        }
        i++;
    }
    
    if (count <= 3) return r;
    return [NSString stringWithFormat:@"%ju days per week", (uintmax_t)count];
}

- (void)updateView {
    // Image, title
    switch (trigger.type) {
    case Trigger::Type::Time:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Time"]];
        [_titleLabel setStringValue:[NSString stringWithFormat:@"At %@",
            _TimeOfDayStringFromSeconds(trigger.time.schedule.time)]];
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
    
//    // Subtitle
//    {
//        NSMutableString* subtitle = [NSMutableString new];
//        
//        switch (trigger.schedule.cadence) {
//        case Trigger::Cadence::Daily:   [subtitle appendString:@"Daily"]; break;
//        case Trigger::Cadence::Weekly:  [subtitle appendString:_WeeklyString(trigger.schedule.weekDays)]; break;
//        case Trigger::Cadence::Monthly: [subtitle appendString:@"Monthly"]; break;
//        case Trigger::Cadence::Yearly:  [subtitle appendString:@"Yearly"]; break;
//        }
//        
//        switch (trigger.type) {
//        case Trigger::Type::Time:
//            break;
//        case Trigger::Type::Motion:
//        case Trigger::Type::Button:
//            if (trigger.schedule.timeLimit.enable) {
//                [subtitle appendFormat:@", %@ – %@",
//                    _TimeOfDayStringFromSeconds(trigger.schedule.timeLimit.start),
//                    _TimeOfDayStringFromSeconds(trigger.schedule.timeLimit.end)];
//            }
//            break;
//        default:
//            abort();
//        }
//        
//        [_subtitleLabel setStringValue:subtitle];
//    }
    
//    // Description
//    {
//        NSMutableString* desc = [NSMutableString stringWithFormat:@"capture %ju image%s",
//            (uintmax_t)trigger.capture.count, (trigger.capture.count!=1 ? "s" : "")];
//        if (trigger.capture.count>1 && trigger.capture.interval.value) {
//            [desc appendFormat:@" (%ju%s interval)",
//                (uintmax_t)trigger.capture.interval.value,
//                _SuffixForDurationUnit(trigger.capture.interval.unit)];
//        }
//        [_descriptionLabel setStringValue:desc];
//    }
}

@end


#define ListItem CaptureTriggersView_ListItem






























@implementation CaptureTriggersView {
    IBOutlet NSView* _nibView;
    
    IBOutlet NSTableView* _tableView;
    
    // Schedule
    IBOutlet NSView*        _schedule_ContainerView;
    
    IBOutlet NSView*        _schedule_Time_View;
    IBOutlet NSTextField*   _schedule_Time_TimeField;
    IBOutlet NSView*        _schedule_Time_DaySelectorContainerView;
    IBOutlet NSPopUpButton* _schedule_Time_CadenceMenu;
    
    IBOutlet NSView*        _schedule_Motion_View;
    IBOutlet NSButton*      _schedule_Motion_LimitTime_Checkbox;
    IBOutlet NSTextField*   _schedule_Motion_LimitTime_TimeStartField;
    IBOutlet NSTextField*   _schedule_Motion_LimitTime_TimeEndField;
    IBOutlet NSButton*      _schedule_Motion_LimitDays_Checkbox;
    IBOutlet NSPopUpButton* _schedule_Motion_LimitDays_Menu;
    IBOutlet NSView*        _schedule_Motion_DaySelectorContainerView;
    
    IBOutlet NSView*             _weeklyDaySelector_View;
    IBOutlet NSSegmentedControl* _weeklyDaySelector_Control;
    
    IBOutlet NSView*        _monthlyDaySelector_View;
    IBOutlet NSTextField*   _monthlyDaySelector_Field;
    
    IBOutlet NSView*        _yearlyDaySelector_View;
    IBOutlet NSTextField*   _yearlyDaySelector_Field;
    
    // Capture
    IBOutlet NSTextField*        _capture_CountField;
    IBOutlet NSTextField*        _capture_IntervalField;
    IBOutlet NSPopUpButton*      _capture_IntervalUnitMenu;
    IBOutlet NSSegmentedControl* _capture_FlashLEDsControl;
    
    // Constraints
    IBOutlet NSView*        _constraints_ContainerView;
    IBOutlet NSView*        _constraints_MotionDetailView;
    IBOutlet NSButton*      _constraints_IgnoreTrigger_Checkbox;
    IBOutlet NSTextField*   _constraints_IgnoreTrigger_DurationField;
    IBOutlet NSPopUpButton* _constraints_IgnoreTrigger_DurationUnitMenu;
    
    IBOutlet NSButton*      _constraints_MaxTriggerCount_Checkbox;
    IBOutlet NSTextField*   _constraints_MaxTriggerCount_Field;
    
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

static void _SetContainerSubview(NSView* container, NSView* subview) {
    [subview removeFromSuperview];
    [container setSubviews:@[]];
    if (!subview) return;
    
    [container addSubview:subview];
    
    NSMutableArray* constraints = [NSMutableArray new];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=0)-[subview]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(subview)]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[subview]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(subview)]];
    
//    if (subview->alignLeadingView) {
//        [constraints addObject:[[subview->alignLeadingView leadingAnchor] constraintEqualToAnchor:[alignLeadingView leadingAnchor]]];
//    }
    
    [NSLayoutConstraint activateConstraints:constraints];
}

static void _Load(const bool& x, NSButton* checkbox) {
    [checkbox setState:(x ? NSControlStateValueOn : NSControlStateValueOff)];
}

static void _Store(bool& x, NSButton* checkbox) {
    x = ([checkbox state] == NSControlStateValueOn);
}

static void _Load(const Trigger::Cadence& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    std::string xstr = StringFromCadence(x);
    xstr[0] = std::toupper(xstr[0]);
    [menu selectItemWithTitle:@(xstr.c_str())];
}

static void _Store(Trigger::Cadence& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    x = CadenceFromString([[menu titleOfSelectedItem] UTF8String]);
}

static void _LoadTime(const uint32_t& x, NSTextField* field) {
    [field setStringValue:_TimeOfDayStringFromSeconds(x)];
}

static void _StoreTime(uint32_t& x, NSTextField* field) {
    x = _SecondsFromTimeOfDayString([field stringValue]);
}

static void _Load(const uint32_t& x, NSTextField* field) {
    [field setObjectValue:@(x)];
}

static void _Store(uint32_t& x, NSTextField* field) {
    x = (uint32_t)[field integerValue];
}

static void _Load(const Trigger::Duration::Unit& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    [menu selectItemWithTitle:@(StringFromUnit(x).c_str())];
}

static void _Store(Trigger::Duration::Unit& x, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    const std::string xstr = [[menu titleOfSelectedItem] UTF8String];
    x = UnitFromString([[menu titleOfSelectedItem] UTF8String]);
}

static void _Load(const Trigger::WeekDays& x, NSSegmentedControl* control) {
    using X = std::remove_reference_t<decltype(x)>;
    size_t idx = 0;
    for (auto y : { X::Mon, X::Tue, X::Wed, X::Thu, X::Fri, X::Sat, X::Sun }) {
        [control setSelected:(std::to_underlying(x) & std::to_underlying(y)) forSegment:idx];
        idx++;
    }
}

static void _Store(Trigger::WeekDays& x, NSSegmentedControl* control) {
    using X = std::remove_reference_t<decltype(x)>;
    std::underlying_type_t<X> r = 0;
    size_t idx = 0;
    for (auto y : { X::Mon, X::Tue, X::Wed, X::Thu, X::Fri, X::Sat, X::Sun }) {
        r |= ([control isSelectedForSegment:idx] ? std::to_underlying(y) : 0);
        idx++;
    }
    x = static_cast<X>(r);
}

static void _Load(const Trigger::MonthDays& x, NSTextField* field) {
    using X = std::remove_reference_t<decltype(x)>;
    #warning TODO: implement
}

static void _Store(Trigger::MonthDays& x, NSTextField* control) {
    using X = std::remove_reference_t<decltype(x)>;
    #warning TODO: implement
}

static void _Load(const Trigger::YearDays& x, NSTextField* field) {
    using X = std::remove_reference_t<decltype(x)>;
    #warning TODO: implement
}

static void _Store(Trigger::YearDays& x, NSTextField* control) {
    using X = std::remove_reference_t<decltype(x)>;
    #warning TODO: implement
}

static void _Load(const Trigger::LEDs& x, NSSegmentedControl* control) {
    using X = std::remove_reference_t<decltype(x)>;
    size_t idx = 0;
    for (auto y : { X::Green, X::Red }) {
        [control setSelected:(std::to_underlying(x) & std::to_underlying(y)) forSegment:idx];
        idx++;
    }
}

static void _Store(Trigger::LEDs& x, NSSegmentedControl* control) {
    using X = std::remove_reference_t<decltype(x)>;
    std::underlying_type_t<X> r = 0;
    size_t idx = 0;
    for (auto y : { X::Green, X::Red }) {
        r |= ([control isSelectedForSegment:idx] ? std::to_underlying(y) : 0);
        idx++;
    }
    x = static_cast<X>(r);
}

- (void)_loadViewFromModel:(const Trigger&)trigger {
    switch (trigger.type) {
    case Trigger::Type::Time: {
        auto& x = trigger.time;
        
        // Schedule
        {
            _SetContainerSubview(_schedule_ContainerView, _schedule_Time_View);
            _LoadTime(x.schedule.time, _schedule_Time_TimeField);
            _Load(x.schedule.cadence, _schedule_Time_CadenceMenu);
            switch (x.schedule.cadence) {
            case Trigger::Cadence::Daily:
                _SetContainerSubview(_schedule_Time_DaySelectorContainerView, nil);
                break;
            case Trigger::Cadence::Weekly:
                _SetContainerSubview(_schedule_Time_DaySelectorContainerView, _weeklyDaySelector_View);
                _Load(x.schedule.weekDays, _weeklyDaySelector_Control);
                break;
            case Trigger::Cadence::Monthly:
                _SetContainerSubview(_schedule_Time_DaySelectorContainerView, _monthlyDaySelector_View);
                break;
            case Trigger::Cadence::Yearly:
                _SetContainerSubview(_schedule_Time_DaySelectorContainerView, _yearlyDaySelector_View);
                break;
            }
        }
        
        // Capture
        {
            _Load(x.capture.count, _capture_CountField);
            _Load(x.capture.interval.value, _capture_IntervalField);
            _Load(x.capture.interval.unit, _capture_IntervalUnitMenu);
            _Load(x.capture.flashLEDs, _capture_FlashLEDsControl);
        }
        
        // Limits
        {
            _SetContainerSubview(_constraints_ContainerView, nil);
            _Load(x.constraints.maxTotalTriggerCount.enable, _constraints_MaxTotalTriggerCount_Checkbox);
            _Load(x.constraints.maxTotalTriggerCount.count, _constraints_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = trigger.motionButton;
        
        // Schedule
        {
            _SetContainerSubview(_schedule_ContainerView, _schedule_Motion_View);
            
            _Load(x.schedule.timeLimit.enable, _schedule_Motion_LimitTime_Checkbox);
            _LoadTime(x.schedule.timeLimit.start, _schedule_Motion_LimitTime_TimeStartField);
            _LoadTime(x.schedule.timeLimit.end, _schedule_Motion_LimitTime_TimeEndField);
            _Load(x.schedule.dayLimit.enable, _schedule_Motion_LimitDays_Checkbox);
            _Load(x.schedule.dayLimit.cadence, _schedule_Time_CadenceMenu);
        }
        
        // Capture
        {
            _Load(x.capture.count, _capture_CountField);
            _Load(x.capture.interval.value, _capture_IntervalField);
            _Load(x.capture.interval.unit, _capture_IntervalUnitMenu);
            _Load(x.capture.flashLEDs, _capture_FlashLEDsControl);
        }
        
        // Limits
        {
            _SetContainerSubview(_constraints_ContainerView, _constraints_MotionDetailView);
            
            _Load(x.constraints.ignoreTriggerDuration.enable, _constraints_IgnoreTrigger_Checkbox);
            _Load(x.constraints.ignoreTriggerDuration.duration.value, _constraints_IgnoreTrigger_DurationField);
            _Load(x.constraints.ignoreTriggerDuration.duration.unit, _constraints_IgnoreTrigger_DurationUnitMenu);
            
            _Load(x.constraints.maxTriggerCount.enable, _constraints_MaxTriggerCount_Checkbox);
            _Load(x.constraints.maxTriggerCount.count, _constraints_MaxTriggerCount_Field);
            
            _Load(x.constraints.maxTotalTriggerCount.enable, _constraints_MaxTotalTriggerCount_Checkbox);
            _Load(x.constraints.maxTotalTriggerCount.count, _constraints_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    default:
        abort();
    }
}





//static void _Load(const Trigger::Duration& x, NSTextField* field, NSPopUpButton* menu) {
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
    switch (trigger.type) {
    case Trigger::Type::Time: {
        auto& x = trigger.time;
        
        // Schedule
        {
            _StoreTime(x.schedule.time, _schedule_Time_TimeField);
            _Store(x.schedule.cadence, _schedule_Time_CadenceMenu);
            switch (x.schedule.cadence) {
            case Trigger::Cadence::Daily:
                break;
            case Trigger::Cadence::Weekly:
                _Store(x.schedule.weekDays, _weeklyDaySelector_Control);
                break;
            case Trigger::Cadence::Monthly:
                _Store(x.schedule.monthDays, _monthlyDaySelector_Field);
                break;
            case Trigger::Cadence::Yearly:
                _Store(x.schedule.yearDays, _yearlyDaySelector_Field);
                break;
            }
        }
        
        // Capture
        {
            _Store(x.capture.count, _capture_CountField);
            _Store(x.capture.interval.value, _capture_IntervalField);
            _Store(x.capture.interval.unit, _capture_IntervalUnitMenu);
            _Store(x.capture.flashLEDs, _capture_FlashLEDsControl);
        }
        
        // Limits
        {
            _Store(x.constraints.maxTotalTriggerCount.enable, _constraints_MaxTotalTriggerCount_Checkbox);
            _Store(x.constraints.maxTotalTriggerCount.count, _constraints_MaxTotalTriggerCount_Field);
        }
        
        break;
    }
    
    case Trigger::Type::Motion:
    case Trigger::Type::Button: {
        auto& x = trigger.motionButton;
        
        // Schedule
        {
            _Store(x.schedule.timeLimit.enable, _schedule_Motion_LimitTime_Checkbox);
            _StoreTime(x.schedule.timeLimit.start, _schedule_Motion_LimitTime_TimeStartField);
            _StoreTime(x.schedule.timeLimit.end, _schedule_Motion_LimitTime_TimeEndField);
            _Store(x.schedule.dayLimit.enable, _schedule_Motion_LimitDays_Checkbox);
            _Store(x.schedule.dayLimit.cadence, _schedule_Time_CadenceMenu);
        }
        
        // Capture
        {
            _Store(x.capture.count, _capture_CountField);
            _Store(x.capture.interval.value, _capture_IntervalField);
            _Store(x.capture.interval.unit, _capture_IntervalUnitMenu);
            _Store(x.capture.flashLEDs, _capture_FlashLEDsControl);
        }
        
        // Limits
        {
            _Store(x.constraints.ignoreTriggerDuration.enable, _constraints_IgnoreTrigger_Checkbox);
            _Store(x.constraints.ignoreTriggerDuration.duration.value, _constraints_IgnoreTrigger_DurationField);
            _Store(x.constraints.ignoreTriggerDuration.duration.unit, _constraints_IgnoreTrigger_DurationUnitMenu);
            
            _Store(x.constraints.maxTriggerCount.enable, _constraints_MaxTriggerCount_Checkbox);
            _Store(x.constraints.maxTriggerCount.count, _constraints_MaxTriggerCount_Field);
            
            _Store(x.constraints.maxTotalTriggerCount.enable, _constraints_MaxTotalTriggerCount_Checkbox);
            _Store(x.constraints.maxTotalTriggerCount.count, _constraints_MaxTotalTriggerCount_Field);
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
