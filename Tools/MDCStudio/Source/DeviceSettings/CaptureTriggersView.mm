#import "CaptureTriggersView.h"
#import <vector>
#import "Toastbox/Mac/Util.h"

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
    
    Type type = Type::Time;
    
    struct [[gnu::packed]] {
        uint32_t start = 0;
        uint32_t end = 0;
        RepeatInterval repeatInterval = RepeatInterval::Daily;
        union {
            WeekDays weekDays;
            MonthDays monthDays;
            YearDays yearDays;
        };
    } time;
    
    struct [[gnu::packed]] {
        uint32_t count = 0;
        uint32_t intervalMs = 0;
        LEDs flashLEDs = LEDs::None;
    } capture;
    
    struct [[gnu::packed]] {
        uint32_t ignoreTriggerDurationMs = 0;
        uint32_t maxTriggerCount = 0;
        uint32_t maxTotalTriggerCount = 0;
    } constraints;
};

struct [[gnu::packed]] Triggers {
    Trigger triggers[32];
    uint8_t triggersCount = 0;
};










@interface CaptureTriggersView_ListItem : NSTableCellView
@end

@implementation CaptureTriggersView_ListItem {
@private
    IBOutlet NSImageView* _imageView;
    IBOutlet NSTextField* _label;
@public
    Trigger trigger;
}

- (void)updateView {
    switch (trigger.type) {
    case Trigger::Type::Time:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Time"]];
        break;
    case Trigger::Type::Motion:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Motion"]];
        break;
    case Trigger::Type::Button:
        [_imageView setImage:[NSImage imageNamed:@"CaptureTriggers-Icon-Button"]];
        break;
    default:
        abort();
    }
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
    
//    [self _loadViewForModel:self->_triggers.triggers[0]];
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

- (void)_loadViewForModel:(const Trigger&)trigger {
    // Time
    {
        switch (trigger.type) {
        case Trigger::Type::Time:
            _ShowDetailView(_timeContainerView, _repeatIntervalButton, _timeDetailView);
            [_timeField setStringValue:[NSString stringWithFormat:@"%@", @(trigger.time.start)]];
            break;
        case Trigger::Type::Motion:
        case Trigger::Type::Button:
            _ShowDetailView(_timeContainerView, _repeatIntervalButton, _timeRangeDetailView);
            [_timeStartField setStringValue:[NSString stringWithFormat:@"%@", @(trigger.time.start)]];
            [_timeEndField setStringValue:[NSString stringWithFormat:@"%@", @(trigger.time.end)]];
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
        [_captureIntervalField setObjectValue:@(trigger.capture.intervalMs)];
        #warning TODO: _captureIntervalUnitButton: select correct element depending on value
        [_captureIntervalUnitButton selectItemAtIndex:0];
        
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
        
        [_ignoreTriggerCheckbox setState:(trigger.constraints.ignoreTriggerDurationMs ? NSControlStateValueOn : NSControlStateValueOff)];
        [_ignoreTriggerDurationField setObjectValue:@(trigger.constraints.ignoreTriggerDurationMs)];
        #warning TODO: _ignoreTriggerDurationUnitButton: select correct element depending on value
        [_ignoreTriggerDurationUnitButton selectItemAtIndex:0];
        
        [_maxTriggerCountCheckbox setState:(trigger.constraints.maxTriggerCount ? NSControlStateValueOn : NSControlStateValueOff)];
        [_maxTriggerCountField setObjectValue:@(trigger.constraints.maxTriggerCount)];
        
        [_maxTotalTriggerCountCheckbox setState:(trigger.constraints.maxTotalTriggerCount ? NSControlStateValueOn : NSControlStateValueOff)];
        [_maxTotalTriggerCountField setObjectValue:@(trigger.constraints.maxTotalTriggerCount)];
        
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
        trigger.time.start = (uint32_t)[_timeField integerValue];
        break;
    case Trigger::Type::Motion:
    case Trigger::Type::Button:
        trigger.time.start = (uint32_t)[_timeStartField integerValue];
        trigger.time.end = (uint32_t)[_timeEndField integerValue];
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
    trigger.capture.intervalMs = (uint32_t)[_captureIntervalField integerValue];
    #warning TODO: trigger.capture.intervalMs: consider unit popup button!
    _Store(trigger.capture.flashLEDs, _flashLEDsControl);
    
    #warning TODO: ignoreTriggerDurationMs: consider unit popup button!
    trigger.constraints.ignoreTriggerDurationMs = (uint32_t)[_ignoreTriggerDurationField integerValue];
    trigger.constraints.maxTriggerCount = (uint32_t)[_maxTriggerCountField integerValue];
    trigger.constraints.maxTotalTriggerCount = (uint32_t)[_maxTotalTriggerCountField integerValue];
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
    [self _loadViewForModel:item->trigger];
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
    
    [self _loadViewForModel:item->trigger];
    
//    item->trigger;
//    
//    NSLog(@"tableViewSelectionDidChange");
}

@end
