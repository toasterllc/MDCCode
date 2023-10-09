#import "CaptureTriggersView.h"
#import <vector>
#import <optional>
#import <sstream>
#import <iomanip>
#import <cmath>
#import <string>
#import <set>
#import "Toastbox/Mac/Util.h"
#import "Toastbox/RuntimeError.h"
#import "Toastbox/NumForStr.h"
#import "Toastbox/String.h"
#import "Toastbox/Defer.h"
#import "Toastbox/DurationString.h"
#import "DeviceSettings.h"
#import "Calendar.h"
#import "Code/Shared/Clock.h"
#import "BatteryLifeEstimate.h"
#import "DeviceSettings/BatteryLifeView/BatteryLifeView.h"
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
    Calendar::DayOfYear{Calendar::MonthOfYear(7),  Calendar::DayOfMonth(4)},
    Calendar::DayOfYear{Calendar::MonthOfYear(10), Calendar::DayOfMonth(31)},
});

static constexpr DayInterval _DayIntervalInit = DayInterval{ 2 };

//static Repeat& _TriggerRepeatGet(Trigger& t) {
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

static void _TriggerInit(Trigger& t, Trigger::Type type) {
    t.type = type;
    switch (t.type) {
    case Trigger::Type::Time: {
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
            .ledFlash = true,
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
                .type = Repeat::Type::Daily,
            },
        };
        
        x.capture = {
            .count = 1,
            .interval = DeviceSettings::Duration{
                .value = 5,
                .unit = DeviceSettings::Duration::Unit::Seconds,
            },
            .ledFlash = true,
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
    
    case Trigger::Type::Button: {
        auto& x = t.button;
        
        x.capture = {
            .count = 1,
            .interval = DeviceSettings::Duration{
                .value = 5,
                .unit = DeviceSettings::Duration::Unit::Seconds,
            },
            .ledFlash = true,
        };
        
        break;
    }
    
    default: abort();
    }
}

static Trigger _TriggerMake(Trigger::Type type) {
    Trigger x;
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

static std::string StringFromRepeatType(const Repeat::Type& x) {
    using X = std::remove_reference_t<decltype(x)>;
    switch (x) {
    case X::Daily:       return "every day";
    case X::DaysOfWeek:  return "on days";
    case X::DaysOfYear:  return "on dates";
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
    Trigger trigger;
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
    case T::DaysOfWeek:  return _DaysOfWeekDescription(x.DaysOfWeek);
    case T::DaysOfYear:  return _DaysOfYearDescription(x.DaysOfYear);
    case T::DayInterval: return _DayIntervalDescription(x.DayInterval);
    default:             abort();
    }
}

static std::string _CaptureDescription(const Capture& x) {
    std::stringstream ss;
    ss << "capture " << x.count << " image" << (x.count!=1 ? "s" : "");
    if (x.count>1 && x.interval.value>0) {
        ss << " (" << StringFromFloat(x.interval.value);
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
    case Trigger::Type::Time:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Time-Large"]];
        [_titlePrefixLabel setStringValue: @"At"];
        [_titleLabel setStringValue: @((Calendar::StringFromTimeOfDay(trigger.time.schedule.time) + ",").c_str())];
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
        if (repeat.type != Repeat::Type::Daily) {
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


@interface CaptureTriggersView () <NSPopoverDelegate, BatteryLifeViewDelegate>
@end

@implementation CaptureTriggersView {
@public
    IBOutlet NSView*            _nibView;
    IBOutlet NSTableView*       _tableView;
    IBOutlet NSView*            _containerView;
    IBOutlet ContainerSubview*  _detailView;
    IBOutlet NSControl*         _addButton;
    IBOutlet NSControl*         _removeButton;
    IBOutlet NSButton*          _batteryLifeButton;
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
    IBOutlet NSButton*           _capture_LEDFlashCheckbox;
    
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
    
    MSP::Triggers _triggers;
    std::vector<ListItem*> _items;
    bool _actionViewChangedUnderway;
    
    BatteryLifeView* _batteryLifeView;
    NSPopover* _batteryLifePopover;
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
    [self->_batteryLifeButton setHidden:emptyMode];
    [self->_separatorLineOffset setConstant:(emptyMode ? 1000 : 8)];
}

static ListItem* _ListItemAdd(CaptureTriggersView* self, const Trigger& trigger, bool select=false) {
    assert(self);
    NSTableView* tv = self->_tableView;
    ListItem* it = [tv makeViewWithIdentifier:NSStringFromClass([ListItem class]) owner:nil];
    it->trigger = trigger;
    [it updateView];
    
    self->_items.push_back(it);
    const size_t idx = self->_items.size()-1;
    NSIndexSet* idxs = [NSIndexSet indexSetWithIndex:idx];
    [tv insertRowsAtIndexes:idxs withAnimation:NSTableViewAnimationEffectNone];
    if (select) {
        // Make the table view the first responder before changing the selection.
        // This is necessary in case a text field is currently being edited, so that the field commits
        // its changes before we change the table view selection, triggering all fields to be reloaded
        // for the new selection.
        [[tv window] makeFirstResponder:tv];
        [tv selectRowIndexes:idxs byExtendingSelection:false];
        [tv scrollRowToVisible:idx];
    }
    
    _SetEmptyMode(self, false);
    return it;
}


//static ListItem* _ListItemAdd(CaptureTriggersView* self, Trigger::Type type) {
//    assert(self);
//    NSTableView* tv = self->_tableView;
//    ListItem* it = [tv makeViewWithIdentifier:NSStringFromClass([ListItem class]) owner:nil];
//    Trigger& t = it->trigger;
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
    
    [_tableView registerForDraggedTypes:@[_PboardDragItemsType]];
    [_tableView reloadData];
//    _ListItemAdd(self, Trigger::Type::Time);
//    _ListItemAdd(self, Trigger::Type::Motion);
//    _ListItemAdd(self, _TriggerMake(Trigger::Type::Button));
    
    [_dateSelector_Field setPlaceholderString:@(Calendar::DayOfYearPlaceholderString().c_str())];
    
    // By default, be in empty mode
    // We'll exit empty mode if we successfully deserialize the triggers
    _SetEmptyMode(self, true);
    
    // Deserialize data
    try {
        Triggers t;
        Deserialize(t, triggers.source);
        for (auto it=std::begin(t.triggers); it!=std::begin(t.triggers)+t.count; it++) {
            _ListItemAdd(self, *it);
        }
        if (t.count) [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:false];
    } catch (const std::exception& e) {
        printf("[CaptureTriggersView] Failed to deserailize triggers: %s\n", e.what());
    }
    
    _batteryLifeView = [[BatteryLifeView alloc] initWithFrame:{}];
    [_batteryLifeView setDelegate:self];
    [self _updateBatteryLife];
    return self;
}

- (Triggers)_triggers {
    Triggers triggers;
    triggers.count = _items.size();
    size_t i = 0;
    for (ListItem* it : _items) {
        triggers.triggers[i] = it->trigger;
        i++;
    }
    return triggers;
}

template<typename T>
static std::string _RangeString(std::chrono::seconds xmin, std::chrono::seconds xmax, std::string_view unit) {
    const T min = date::floor<T>(xmin);
    const T max = date::floor<T>(xmax);
    std::stringstream ss;
    if (min == max) {
        ss << min.count() << " " << unit;
        if (min.count() != 1) ss << "s";
    } else {
        ss << min.count() << " – " << max.count() << " " << unit;
        if (max.count() != 1) ss << "s";
    }
    return ss.str();
}

- (void)_updateBatteryLife {
    [_batteryLifeView setTriggers:[self triggers]];
    [self _updateBatteryLifeTitle];
}

- (void)_updateBatteryLifeTitle {
    const auto estimate = [_batteryLifeView batteryLifeEstimate];
    constexpr std::chrono::seconds Year = date::days(365);
    constexpr std::chrono::seconds Month = date::days(30);
    std::string title;
    if (estimate.min>Year && estimate.max>Year) {
        title = _RangeString<date::years>(estimate.min, estimate.max, "year").c_str();
    
    } else if (estimate.min>2*Month && estimate.max>2*Month) {
        title = _RangeString<date::months>(estimate.min, estimate.max, "month").c_str();
    
    } else {
        title = _RangeString<date::days>(estimate.min, estimate.max, "day").c_str();
    }
    
    [_batteryLifeButton setTitle:[NSString stringWithFormat:@"  %@", @(title.c_str())]];
}

- (const MSP::Triggers&)triggers {
    _triggers = Convert([self _triggers]);
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
        [field setStringValue:@(StringFromFloat(x.value).c_str())];
        [menu selectItemWithTitle:@(DeviceSettings::Duration::StringFromUnit(x.unit).c_str())];
    } else {
        const std::string xstr = [[menu titleOfSelectedItem] UTF8String];
        try {
            x.value = std::max(0.f, FloatFromString([[field stringValue] UTF8String]));
        } catch (...) {}
        x.unit = DeviceSettings::Duration::UnitFromString([[menu titleOfSelectedItem] UTF8String]);
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
    
    _Copy<T_Forward>(x.ledFlash, v._capture_LEDFlashCheckbox);
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
            if constexpr (T_Forward) _ContainerSubviewSet(v._battery_ContainerView, nil);
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
    
    ListItem* it = [self _selectedItem];
    if (it) {
        Trigger& trigger = it->trigger;
        
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
            case Trigger::Type::Time:   _TriggerInitRepeat(trigger.time.schedule.repeat); break;
            case Trigger::Type::Motion: _TriggerInitRepeat(trigger.motion.schedule.repeat); break;
            default:                    abort();
            }
        }
        
        _Load(self, trigger);
        [it updateView];
    }
}

- (IBAction)_actionViewChanged:(id)sender {
    _StoreLoad(self);
    [self _updateBatteryLife];
}

- (IBAction)_actionRepeatMenuChanged:(id)sender {
    _StoreLoad(self, true);
    [self _updateBatteryLife];
}

- (IBAction)_actionAddTimeTrigger:(id)sender {
    _ListItemAdd(self, _TriggerMake(Trigger::Type::Time), true);
    [self _updateBatteryLife];
}

- (IBAction)_actionAddMotionTrigger:(id)sender {
    _ListItemAdd(self, _TriggerMake(Trigger::Type::Motion), true);
    [self _updateBatteryLife];
}

- (IBAction)_actionAddButtonTrigger:(id)sender {
    _ListItemAdd(self, _TriggerMake(Trigger::Type::Button), true);
    [self _updateBatteryLife];
}

- (IBAction)_actionRemove:(id)sender {
    NSInteger idx = [_tableView selectedRow];
    if (idx < 0) return;
    _ListItemRemove(self, idx);
    [self _updateBatteryLife];
}

- (IBAction)_actionBatteryLife:(id)sender {
    if (!_batteryLifePopover) {
        NSViewController* vc = [NSViewController new];
        [vc setView:_batteryLifeView];
        
        _batteryLifePopover = [NSPopover new];
        [_batteryLifePopover setDelegate:self];
        [_batteryLifePopover setBehavior:NSPopoverBehaviorSemitransient];
//        [_batteryLifePopover setBehavior:NSPopoverBehaviorTransient];
        [_batteryLifePopover setContentViewController:vc];
    }
    [_batteryLifePopover showRelativeToRect:{} ofView:_batteryLifeButton preferredEdge:NSRectEdgeMaxY];
}

- (BOOL)popoverShouldClose:(NSPopover*)popover {
    NSLog(@"popoverShouldClose");
    return true;
}

- (void)batteryLifeViewChanged:(BatteryLifeView*)view {
    [self _updateBatteryLifeTitle];
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
