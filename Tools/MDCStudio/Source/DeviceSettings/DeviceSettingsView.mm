#import "DeviceSettingsView.h"

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
    
    using WeekDays = uint8_t;
    struct WeekDays_ {
        static constexpr WeekDays Mon = 1<<0;
        static constexpr WeekDays Tue = 1<<1;
        static constexpr WeekDays Wed = 1<<2;
        static constexpr WeekDays Thu = 1<<3;
        static constexpr WeekDays Fri = 1<<4;
        static constexpr WeekDays Sat = 1<<5;
        static constexpr WeekDays Sun = 1<<6;
    };
    
    using MonthDays = uint32_t;
    using YearDays = uint32_t[12];
    
    using LEDs = uint8_t;
    struct LEDs_ {
        static constexpr LEDs Green = 1<<0;
        static constexpr LEDs Red = 1<<1;
    };
    
    enum class LimitPeriod : uint8_t {
        Activation,
        Minute,
        Hour,
        Day,
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
        LEDs flashLEDs = 0;
    } capture;
    
    struct [[gnu::packed]] {
        uint32_t triggerCount = 0;
        LimitPeriod triggerCountPeriod = LimitPeriod::Activation;
        uint32_t triggerCountTotal = 0;
    } limits;
};

struct [[gnu::packed]] Triggers {
    Trigger triggers[32];
    uint8_t triggersCount = 0;
};



@interface DeviceSettingsView_DetailView : NSView
@end

@implementation DeviceSettingsView_DetailView {
@public
    IBOutlet NSView* alignLeadingView;
}
@end

@implementation DeviceSettingsView {
    IBOutlet NSView* _nibView;
    
    // Time
    IBOutlet NSView* _timeContainerView;
    IBOutlet DeviceSettingsView_DetailView* _timeDetailView;
    IBOutlet DeviceSettingsView_DetailView* _timeRangeDetailView;
    IBOutlet NSPopUpButton* _repeatIntervalButton;
    IBOutlet NSView* _repeatIntervalContainerView;
    IBOutlet DeviceSettingsView_DetailView* _weeklyDetailView;
    IBOutlet DeviceSettingsView_DetailView* _monthlyDetailView;
    IBOutlet DeviceSettingsView_DetailView* _yearlyDetailView;
    IBOutlet NSTextField* _timeField;
    IBOutlet NSTextField* _timeStartField;
    IBOutlet NSTextField* _timeEndField;
    
    // Capture
    IBOutlet NSTextField* _captureCountField;
    IBOutlet NSTextField* _captureIntervalField;
    IBOutlet NSPopUpButton* _captureIntervalUnitButton;
    
    IBOutlet NSButton* _flashLEDCheckbox;
    IBOutlet NSPopUpButton* _flashLEDButton;
    
    // Limits
    IBOutlet NSView* _limitsContainerView;
    IBOutlet DeviceSettingsView_DetailView* _limitsDetailView;
    IBOutlet NSButton* _ignoreTriggerCheckbox;
    IBOutlet NSTextField* _ignoreTriggerIntervalField;
    IBOutlet NSPopUpButton* _ignoreTriggerIntervalUnitButton;
    
    IBOutlet NSButton* _limitTriggerCountCheckbox;
    IBOutlet NSTextField* _limitTriggerCountField;
    
    IBOutlet NSButton* _limitTotalTriggerCountCheckbox;
    IBOutlet NSTextField* _limitTotalTriggerCountField;
    
    Triggers _triggers;
}

static void _Init(DeviceSettingsView* self) {
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
    
    [self _loadViewForModel:self->_triggers.triggers[0]];
}

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

static void _ShowDetailView(NSView* container, NSView* alignLeadingView, DeviceSettingsView_DetailView* detailView) {
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
    }
    
    // Capture
    {
        [_captureCountField setObjectValue:@(trigger.capture.count)];
        [_captureIntervalField setObjectValue:@(trigger.capture.intervalMs)];
        #warning TODO: convert trigger.capture.interval to the appropriate unit (seconds/minutes/hours), and select the respective item in _captureIntervalUnitButton
        [_captureIntervalUnitButton selectItemAtIndex:0];
        
        const bool green = trigger.capture.flashLEDs & Trigger::LEDs_::Green;
        const bool red = trigger.capture.flashLEDs & Trigger::LEDs_::Red;
        if (green && red) {
            [_flashLEDCheckbox setState:NSControlStateValueOn];
            [_flashLEDButton selectItemWithTitle:@"Both"];
        } else if (green) {
            [_flashLEDCheckbox setState:NSControlStateValueOn];
            [_flashLEDButton selectItemWithTitle:@"Green"];
        } else if (red) {
            [_flashLEDCheckbox setState:NSControlStateValueOn];
            [_flashLEDButton selectItemWithTitle:@"Red"];
        } else {
            [_flashLEDCheckbox setState:NSControlStateValueOff];
            [_flashLEDButton selectItemWithTitle:@"Green"];
        }
    }
    
    // Limits
    {
        switch (trigger.type) {
        case Trigger::Type::Time:
//            _ShowDetailView(_limitsContainerView, _limitTotalTriggerCountField, nil);
//            break;
        case Trigger::Type::Motion:
        case Trigger::Type::Button:
            _ShowDetailView(_limitsContainerView, _limitTotalTriggerCountField, _limitsDetailView);
            break;
        default:
            abort();
        }
        
        
        [_limitTriggerCountCheckbox setState:(trigger.limits.triggerCount ? NSControlStateValueOn : NSControlStateValueOff)];
        [_limitTriggerCountField setObjectValue:@(trigger.limits.triggerCount)];
        
        [_limitTotalTriggerCountCheckbox setState:(trigger.limits.triggerCountTotal ? NSControlStateValueOn : NSControlStateValueOff)];
        [_limitTotalTriggerCountField setObjectValue:@(trigger.limits.triggerCountTotal)];
        
//        [_limitTriggerCountPeriodButton selectItemAtIndex:(NSInteger)trigger.limits.triggerCountPeriod];
    }
}

- (void)_storeViewToModel:(Trigger&)trigger {
    
}

- (IBAction)_action_captureCount:(id)sender {
    
}

- (IBAction)_action_captureInterval:(id)sender {
    
}

- (IBAction)_action_flashLED:(id)sender {
    
}

- (IBAction)_action_limitTriggerCount:(id)sender {
    
}

- (IBAction)_action_limitTotalTriggerCount:(id)sender {
    
}

@end
