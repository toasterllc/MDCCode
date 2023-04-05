#import "DeviceSettingsView.h"
#import "Toastbox/Mac/Util.h"

@implementation DeviceSettingsView {
@public
    IBOutlet NSView* _nibView;
    IBOutlet NSTabView* _tabView;
    IBOutlet NSSegmentedControl* _segmentedControl;
    IBOutlet NSView* _headerBackground;
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
//    [self->_tabView selectTabViewItem:[self->_tabView tabViewItemAtIndex:0]];
    [self->_segmentedControl setSelectedSegment:0];
    [self _actionSectionChanged:nil];
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

- (IBAction)_actionSectionChanged:(id)sender {
    const NSInteger idx = [_segmentedControl selectedSegment];
    [_tabView selectTabViewItemAtIndex:idx];
    
    NSView* view = [[_tabView tabViewItemAtIndex:idx] view];
    NSLayoutYAxisAnchor*const anchor = [view deviceSettingsView_HeaderBottomAnchor];
    const CGFloat offset = [view deviceSettingsView_HeaderBottomAnchorOffset];
    [[[_headerBackground bottomAnchor] constraintEqualToAnchor:anchor constant:offset] setActive:true];
}

- (IBAction)_actionDismiss:(id)sender {
    [[[self window] sheetParent] endSheet:[self window]];
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
