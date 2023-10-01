#import "DeviceImageGridHeaderView.h"

@implementation DeviceImageGridHeaderView {
    id<DeviceImageGridHeaderViewDelegate> _delegate;
    IBOutlet NSView* _nibView;
    
    IBOutlet NSLayoutConstraint* _height;
    
    IBOutlet NSTextField* _statusLabel;
    
    IBOutlet NSView* _loadPhotosContainerView;
    IBOutlet NSTextField* _loadPhotosCountLabel;
}

- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device {
    if (!(self = [super initWithFrame:{}])) return nil;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    NSView* nibView = self->_nibView;
    [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:_nibView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    
    [self setLoadCount:0];
    return self;
}

- (NSSize)intrinsicContentSize {
    return { NSViewNoInstrinsicMetric, [_height constant] };
}

- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x {
    _delegate = x;
}

- (void)setLoadCount:(NSUInteger)x {
    if (x) {
        [_statusLabel setStringValue:[NSString stringWithFormat:@"%@", @(x)]];
        [_loadPhotosContainerView setHidden:false];
    } else {
        [_loadPhotosContainerView setHidden:true];
    }
}

- (void)setStatus:(NSString*)status {
    [_statusLabel setStringValue:status];
}

- (IBAction)load:(id)sender {
    [_delegate deviceImageGridHeaderViewLoad:self];
}

@end
