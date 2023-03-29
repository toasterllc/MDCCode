#import "DeviceSettingsView.h"

@implementation DeviceSettingsView {
    IBOutlet NSView* _nibView;
    
    IBOutlet NSView* _timeContainerView;
    IBOutlet NSView* _repeatIntervalContainerView;
    
    IBOutlet NSView* _timeView;
    IBOutlet NSView* _timeRangeView;
    IBOutlet NSView* _weeklyDaySelectorView;
    IBOutlet NSView* _monthlyDaySelectorView;
    IBOutlet NSView* _yearlyDaySelectorView;
    
    // Time
    IBOutlet NSPopUpButton* _repeatIntervalButton;
    
    // Capture
    IBOutlet NSTextField* _captureCountField;
    IBOutlet NSTextField* _captureIntervalField;
    IBOutlet NSPopUpButton* _captureIntervalUnitButton;
    
    IBOutlet NSButton* _flashLEDCheckbox;
    IBOutlet NSPopUpButton* _flashLEDButton;
    
    // Limits
    IBOutlet NSButton* _limitTriggerCountCheckbox;
    IBOutlet NSTextField* _limitTriggerCountField;
    IBOutlet NSPopUpButton* _limitTriggerCountPeriodButton;
    
    IBOutlet NSButton* _limitTotalTriggerCountCheckbox;
    IBOutlet NSTextField* _limitTotalTriggerCountField;
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
