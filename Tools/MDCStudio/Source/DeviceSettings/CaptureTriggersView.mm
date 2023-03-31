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
    
    enum class RepeatInterval : uint8_t {
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
        
        uint32_t value = 0;
        Unit unit = Unit::Seconds;
    };
    
    Type type = Type::Time;
    
    struct [[gnu::packed]] {
        union {
            uint32_t time;
            
            struct [[gnu::packed]] {
                bool enable;
                uint32_t start;
                uint32_t end;
            } timeRange;
        };
        RepeatInterval repeatInterval = RepeatInterval::Daily;
        union {
            WeekDays weekDays;
            MonthDays monthDays;
            YearDays yearDays;
        };
    } time;
    
    struct [[gnu::packed]] {
        uint32_t count = 0;
        Duration interval;
        LEDs flashLEDs = LEDs::None;
    } capture;
    
    struct [[gnu::packed]] {
        struct [[gnu::packed]] {
            bool enable = false;
            Duration duration;
        } ignoreTriggerDuration;
        
        struct [[gnu::packed]] {
            bool enable = false;
            uint32_t count = 0;
        } maxTriggerCount;
        
        struct [[gnu::packed]] {
            bool enable = false;
            uint32_t count = 0;
        } maxTotalTriggerCount;
    } constraints;
};

struct [[gnu::packed]] Triggers {
    Trigger triggers[32];
    uint8_t triggersCount = 0;
};






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

- (void)updateView {
    
    
    switch (trigger.type) {
    case Trigger::Type::Time:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Time"]];
        [_titleLabel setStringValue:[NSString stringWithFormat:@"At %@",
            _TimeOfDayStringFromSeconds(trigger.time.time)]];
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
    
    NSMutableString* desc = [NSMutableString stringWithFormat:@"capture %ju image%s",
        (uintmax_t)trigger.capture.count, (trigger.capture.count!=1 ? "s" : "")];
    if (trigger.capture.count>1 && trigger.capture.interval.value) {
        [desc appendFormat:@" (%ju%s interval)",
            (uintmax_t)trigger.capture.interval.value,
            _SuffixForDurationUnit(trigger.capture.interval.unit)];
    }
    [_descriptionLabel setStringValue:desc];
    
    
}

@end


#define ListItem CaptureTriggersView_ListItem































@interface CaptureTriggersView_DetailView : NSView
@end

@implementation CaptureTriggersView_DetailView {
@public
    IBOutlet NSView* alignLeadingView;
}
@end

@implementation CaptureTriggersView {
    IBOutlet NSView* _nibView;
    
    IBOutlet NSTableView* _tableView;
    
    // Time
    IBOutlet NSView* _timeContainerView;
    IBOutlet CaptureTriggersView_DetailView* _timeDetailView;
    IBOutlet CaptureTriggersView_DetailView* _timeRangeDetailView;
    IBOutlet NSPopUpButton* _repeatIntervalButton;
    IBOutlet NSView* _repeatIntervalContainerView;
    IBOutlet CaptureTriggersView_DetailView* _weeklyDetailView;
    IBOutlet NSSegmentedControl* _weekDaysControl;
    IBOutlet CaptureTriggersView_DetailView* _monthlyDetailView;
    IBOutlet NSTextField* _monthDaysField;
    IBOutlet CaptureTriggersView_DetailView* _yearlyDetailView;
    IBOutlet NSTextField* _yearDaysField;
    IBOutlet NSTextField* _timeField;
    IBOutlet NSTextField* _timeStartField;
    IBOutlet NSTextField* _timeEndField;
    
    // Capture
    IBOutlet NSTextField* _captureCountField;
    IBOutlet NSTextField* _captureIntervalField;
    IBOutlet NSPopUpButton* _captureIntervalUnitButton;
    
    IBOutlet NSSegmentedControl* _flashLEDsControl;
    
    // Constraints
    IBOutlet NSView* _constraintsContainerView;
    IBOutlet CaptureTriggersView_DetailView* _constraintsDetailView;
    IBOutlet NSButton* _ignoreTriggerCheckbox;
    IBOutlet NSTextField* _ignoreTriggerDurationField;
    IBOutlet NSPopUpButton* _ignoreTriggerDurationUnitButton;
    
    IBOutlet NSButton* _maxTriggerCountCheckbox;
    IBOutlet NSTextField* _maxTriggerCountField;
    
    IBOutlet NSButton* _maxTotalTriggerCountCheckbox;
    IBOutlet NSTextField* _maxTotalTriggerCountField;
    
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

static void _ShowDetailView(NSView* container, NSView* alignLeadingView, CaptureTriggersView_DetailView* detailView) {
    [detailView removeFromSuperview];
    [container setSubviews:@[]];
    if (!detailView) return;
    
    [container addSubview:detailView];
    
    NSMutableArray* constraints = [NSMutableArray new];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=0)-[detailView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(detailView)]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[detailView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(detailView)]];
    
    if (detailView->alignLeadingView) {
        [constraints addObject:[[detailView->alignLeadingView leadingAnchor] constraintEqualToAnchor:[alignLeadingView leadingAnchor]]];
    }
    
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)_loadViewFromModel:(const Trigger&)trigger {
    // Time
    {
        switch (trigger.type) {
        case Trigger::Type::Time:
            _ShowDetailView(_timeContainerView, _repeatIntervalButton, _timeDetailView);
            [_timeField setStringValue:_TimeOfDayStringFromSeconds(trigger.time.time)];
            break;
        case Trigger::Type::Motion:
        case Trigger::Type::Button:
            _ShowDetailView(_timeContainerView, _repeatIntervalButton, _timeRangeDetailView);
            [_timeStartField setStringValue:_TimeOfDayStringFromSeconds(trigger.time.timeRange.start)];
            [_timeEndField setStringValue:_TimeOfDayStringFromSeconds(trigger.time.timeRange.end)];
            break;
        default:
            abort();
        }
        
        [_repeatIntervalButton selectItemAtIndex:(NSInteger)trigger.time.repeatInterval];
        switch (trigger.time.repeatInterval) {
        case Trigger::RepeatInterval::Daily:
            _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, nil);
            break;
        case Trigger::RepeatInterval::Weekly:
            _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _weeklyDetailView);
            _Load(trigger.time.weekDays, _weekDaysControl);
            break;
        case Trigger::RepeatInterval::Monthly:
            _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _monthlyDetailView);
            break;
        case Trigger::RepeatInterval::Yearly:
            _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _yearlyDetailView);
            break;
        }
    }
    
    // Capture
    {
        [_captureCountField setObjectValue:@(trigger.capture.count)];
        [_captureIntervalField setObjectValue:@(trigger.capture.interval.value)];
        [_captureIntervalUnitButton selectItemAtIndex:(NSInteger)trigger.capture.interval.unit];
        
        _Load(trigger.capture.flashLEDs, _flashLEDsControl);
    }
    
    // Limits
    {
        switch (trigger.type) {
        case Trigger::Type::Time:
            _ShowDetailView(_constraintsContainerView, _maxTotalTriggerCountField, nil);
            break;
        case Trigger::Type::Motion:
        case Trigger::Type::Button:
            _ShowDetailView(_constraintsContainerView, _maxTotalTriggerCountField, _constraintsDetailView);
            break;
        default:
            abort();
        }
        
        [_ignoreTriggerCheckbox setState:(trigger.constraints.ignoreTriggerDuration.enable ? NSControlStateValueOn : NSControlStateValueOff)];
        _Load(trigger.constraints.ignoreTriggerDuration.duration, _ignoreTriggerDurationField, _ignoreTriggerDurationUnitButton);
        
        [_maxTriggerCountCheckbox setState:(trigger.constraints.maxTriggerCount.enable ? NSControlStateValueOn : NSControlStateValueOff)];
        [_maxTriggerCountField setObjectValue:@(trigger.constraints.maxTriggerCount.count)];
        
        [_maxTotalTriggerCountCheckbox setState:(trigger.constraints.maxTotalTriggerCount.enable ? NSControlStateValueOn : NSControlStateValueOff)];
        [_maxTotalTriggerCountField setObjectValue:@(trigger.constraints.maxTotalTriggerCount.count)];
        
//        [_maxTriggerCountPeriodButton selectItemAtIndex:(NSInteger)trigger.constraints.triggerCountPeriod];
    }
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





static void _Load(const Trigger::Duration& x, NSTextField* field, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    [field setObjectValue:@(x.value)];
    [menu selectItemAtIndex:(NSInteger)x.unit];
}

static void _Store(Trigger::Duration& x, NSTextField* field, NSPopUpButton* menu) {
    using X = std::remove_reference_t<decltype(x)>;
    x.value = (uint32_t)[field integerValue];
    x.unit = (Trigger::Duration::Unit)[menu indexOfSelectedItem];
}








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
//    Type type = Type::Time;
//    
//    struct [[gnu::packed]] {
//        uint32_t start = 0;
//        uint32_t end = 0;
//        RepeatInterval repeatInterval = RepeatInterval::Daily;
//        union {
//            WeekDays weekDays;
//            MonthDays monthDays;
//            YearDays yearDays;
//        };
//    } time;
//    
//    struct [[gnu::packed]] {
//        uint32_t count = 0;
//        uint32_t intervalMs = 0;
//        LEDs flashLEDs = 0;
//    } capture;
//    
//    struct [[gnu::packed]] {
//        uint32_t ignoreTriggerDurationMs = 0;
//        uint32_t maxTriggerCount = 0;
//        uint32_t maxTotalTriggerCount = 0;
//    } constraints;
    
    
    switch (trigger.type) {
    case Trigger::Type::Time:
        try {
            trigger.time.time = _SecondsFromTimeOfDayString([_timeField stringValue]);
        } catch (...) {}
        break;
    case Trigger::Type::Motion:
    case Trigger::Type::Button:
        try {
            trigger.time.timeRange.start = _SecondsFromTimeOfDayString([_timeStartField stringValue]);
        } catch (...) {}
        try {
            trigger.time.timeRange.end = _SecondsFromTimeOfDayString([_timeEndField stringValue]);
        } catch (...) {}
        break;
    default:
        abort();
    }
    
    trigger.time.repeatInterval = (Trigger::RepeatInterval)[_repeatIntervalButton indexOfSelectedItem];
    
    switch (trigger.time.repeatInterval) {
    case Trigger::RepeatInterval::Daily:
        break;
    case Trigger::RepeatInterval::Weekly:
        _Store(trigger.time.weekDays, _weekDaysControl);
        break;
    case Trigger::RepeatInterval::Monthly:
//        trigger.time.monthDays = XXX;
        break;
    case Trigger::RepeatInterval::Yearly:
//        trigger.time.yearDays = XXX;
        break;
    default:
        abort();
    }
    
    trigger.capture.count = (uint32_t)[_captureCountField integerValue];
    _Store(trigger.capture.interval, _captureIntervalField, _captureIntervalUnitButton);
    _Store(trigger.capture.flashLEDs, _flashLEDsControl);
    
    #warning TODO: ignoreTriggerDurationMs: consider unit popup button!
    trigger.constraints.ignoreTriggerDuration.enable = [_ignoreTriggerCheckbox state]==NSControlStateValueOn;
    _Store(trigger.constraints.ignoreTriggerDuration.duration, _ignoreTriggerDurationField, _ignoreTriggerDurationUnitButton);
    
    trigger.constraints.maxTriggerCount.enable = [_maxTriggerCountCheckbox state]==NSControlStateValueOn;
    trigger.constraints.maxTriggerCount.count = (uint32_t)[_maxTriggerCountField integerValue];
    
    trigger.constraints.maxTotalTriggerCount.enable = [_maxTotalTriggerCountCheckbox state]==NSControlStateValueOn;
    trigger.constraints.maxTotalTriggerCount.count = (uint32_t)[_maxTotalTriggerCountField integerValue];
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

- (IBAction)_action_repeatInterval:(id)sender {
    NSInteger idx = [_repeatIntervalButton indexOfSelectedItem];
    switch (idx) {
    case 0:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, nil); break;
    case 1:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _weeklyDetailView); break;
    case 2:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _monthlyDetailView); break;
    case 3:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _yearlyDetailView); break;
    default:    abort();
    }
    
    _ShowDetailView(_timeContainerView, _repeatIntervalButton, _timeDetailView);
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
