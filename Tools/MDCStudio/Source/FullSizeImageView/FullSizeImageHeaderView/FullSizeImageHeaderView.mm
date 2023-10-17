#import "FullSizeImageHeaderView.h"
using namespace MDCStudio;

@implementation FullSizeImageHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSLayoutConstraint* _heightConstraint;
    __weak id<FullSizeImageHeaderViewDelegate> _delegate;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil]
        instantiateWithOwner:self topLevelObjects:nil];
    assert(br);
    
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

- (void)setDelegate:(id<FullSizeImageHeaderViewDelegate>)x {
    _delegate = x;
}

- (IBAction)actionBack:(id)sender {
    [_delegate imageHeaderViewBack:self];
}

@end
