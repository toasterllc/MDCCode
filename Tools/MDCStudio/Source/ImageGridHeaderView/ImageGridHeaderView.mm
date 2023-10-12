#import "ImageGridHeaderView.h"
using namespace MDCStudio;

@implementation ImageGridHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSLayoutConstraint* _heightConstraint;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
    [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
    [self addSubview:_nibView];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|"
        options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
    
    return self;
}

- (NSSize)intrinsicContentSize {
    return { NSViewNoIntrinsicMetric, [_heightConstraint constant] };
}

- (void)setSelection:(MDCStudio::ImageSet)selection {
}

@end
