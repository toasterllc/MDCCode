#import "DeviceSettingsView.h"

@interface DeviceSettingsView_DetailView : NSView
@end

@implementation DeviceSettingsView_DetailView {
@public
    IBOutlet NSView* alignLeadingView;
    IBOutlet NSView* alignTrailingView;
}
@end

@implementation DeviceSettingsView {
    IBOutlet NSView* _nibView;
    
    IBOutlet NSView* _timeContainerView;
    IBOutlet NSView* _repeatIntervalContainerView;
    
    IBOutlet DeviceSettingsView_DetailView* _timeView;
    IBOutlet DeviceSettingsView_DetailView* _timeRangeView;
    IBOutlet DeviceSettingsView_DetailView* _weeklyDaySelectorView;
    IBOutlet DeviceSettingsView_DetailView* _monthlyDaySelectorView;
    IBOutlet DeviceSettingsView_DetailView* _yearlyDaySelectorView;
    
    // Time
//    IBOutlet NSTextField* _repeatIntervalLabel;
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
    NSInteger idx = [_repeatIntervalButton indexOfSelectedItem];
    switch (idx) {
    case 0:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, nil); break;
    case 1:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _weeklyDaySelectorView); break;
    case 2:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _monthlyDaySelectorView); break;
    case 3:     _ShowDetailView(_repeatIntervalContainerView, _repeatIntervalButton, _yearlyDaySelectorView); break;
    default:    abort();
    }
    
    _ShowDetailView(_timeContainerView, _repeatIntervalButton, _timeView);
}

static void _ShowDetailView(NSView* container, NSView* alignLeadingView, DeviceSettingsView_DetailView* detailView) {
    [detailView removeFromSuperview];
    [container setSubviews:@[]];
    if (!detailView) return;
    
    [container addSubview:detailView];
    
    NSMutableArray* constraints = [NSMutableArray new];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[detailView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(detailView)]];
    [constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[detailView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(detailView)]];
    
    if (detailView->alignLeadingView) {
        [constraints addObject:[[detailView->alignLeadingView leadingAnchor] constraintEqualToAnchor:[alignLeadingView leadingAnchor]]];
    }
    
    [NSLayoutConstraint activateConstraints:constraints];
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
