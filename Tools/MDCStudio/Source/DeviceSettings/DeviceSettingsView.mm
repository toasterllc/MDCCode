#import "DeviceSettingsView.h"
#import "Toastbox/Mac/Util.h"

@implementation DeviceSettingsView {
@public
    IBOutlet NSView* _nibView;
    IBOutlet NSTabView* _tabView;
    IBOutlet NSSegmentedControl* _segmentedControl;
    IBOutlet NSView* _headerBackground;
    
    __weak id<DeviceSettingsViewDelegate> _delegate;
}

// MARK: - Creation

- (instancetype)initWithSettings:(const MSP::Settings&)settings
    delegate:(id<DeviceSettingsViewDelegate>)delegate {
    
    if (!(self = [super initWithFrame:{}])) return nil;
    
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
//    [self->_tabView selectTabViewItem:[self->_tabView tabViewItemAtIndex:0]];
    [self->_segmentedControl setSelectedSegment:0];
    [self _actionSectionChanged:nil];
    
    _delegate = delegate;
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

- (IBAction)_actionSectionChanged:(id)sender {
    const NSInteger idx = [_segmentedControl selectedSegment];
    [_tabView selectTabViewItemAtIndex:idx];
    
    NSView* view = [[_tabView tabViewItemAtIndex:idx] view];
//    static int i = 0;
//    i++;
//    if (i > 3) {
    [[[_headerBackground bottomAnchor] constraintEqualToAnchor:[[view deviceSettingsView_HeaderEndView] topAnchor]] setActive:true];
//    }
}

- (IBAction)_actionOK:(id)sender {
    [_delegate deviceSettingsView:self dismiss:true];
}

- (IBAction)_actionCancel:(id)sender {
    [_delegate deviceSettingsView:self dismiss:false];
}

- (const MSP::Settings&)settings {
    abort();
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
