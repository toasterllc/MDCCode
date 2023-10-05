#import "DeviceSettingsView.h"
#import "Toastbox/Mac/Util.h"
#import "CaptureTriggersView/CaptureTriggersView.h"

@implementation DeviceSettingsView {
@public
    MSP::Settings _settings;
    __weak id<DeviceSettingsViewDelegate> _delegate;
    
    IBOutlet NSView* _nibView;
    IBOutlet NSView* _containerView;
    IBOutlet NSView* _headerBackground;
    
    CaptureTriggersView* _captureTriggersView;
}

// MARK: - Creation

- (instancetype)initWithSettings:(const MSP::Settings&)settings
    delegate:(id<DeviceSettingsViewDelegate>)delegate {
    
    if (!(self = [super initWithFrame:{}])) return nil;
    
    _settings = settings;
    _delegate = delegate;
    
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
    
    _captureTriggersView = [[CaptureTriggersView alloc] initWithTriggers:_settings.triggers];
    [_containerView addSubview:_captureTriggersView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_captureTriggersView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_captureTriggersView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_captureTriggersView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_captureTriggersView)]];
    
    [[[_headerBackground bottomAnchor] constraintEqualToAnchor:[[_captureTriggersView deviceSettingsView_HeaderEndView] topAnchor]] setActive:true];
    
    return self;
}

//- (instancetype)initWithFrame:(NSRect)frame {
//    if (!(self = [super initWithFrame:frame])) return nil;
//    _Init(self);
//    return self;
//}
//
//- (instancetype)initWithCoder:(NSCoder*)coder {
//    if (!(self = [super initWithCoder:coder])) return nil;
//    _Init(self);
//    return self;
//}

//- (IBAction)_actionSectionChanged:(id)sender {
//    const NSInteger idx = [_segmentedControl selectedSegment];
//    [_tabView selectTabViewItemAtIndex:idx];
//    
//    NSView* view = [[_tabView tabViewItemAtIndex:idx] view];
////    static int i = 0;
////    i++;
////    if (i > 3) {
//    [[[_headerBackground bottomAnchor] constraintEqualToAnchor:[[view deviceSettingsView_HeaderEndView] topAnchor]] setActive:true];
////    }
//}

- (IBAction)_actionOK:(id)sender {
    // Commit changes for current field
    [[self window] makeFirstResponder:nil];
    [_delegate deviceSettingsView:self dismiss:true];
}

- (IBAction)_actionCancel:(id)sender {
    [_delegate deviceSettingsView:self dismiss:false];
}

- (const MSP::Settings&)settings {
    // Update settings before returning
    _settings.triggers = [_captureTriggersView triggers];
    return _settings;
}

@end


//@interface MyTabView : NSTabView
//@end
//
//@implementation MyTabView
//
//- (instancetype)initWithCoder:(NSCoder*)coder{
//    if (!(self = [super initWithCoder:coder])) return nil;
//    NSLog(@"%@", [self subviews]);
//    NSSegmentedControl
//    [self setTabViewType:NSNoTabsNoBorder];
////    NSLog(@"%@", [self subviews]);
////    [self setTabViewBorderType:NSTabViewBorderTypeNone];
//    return self;
//}
//
//@end
