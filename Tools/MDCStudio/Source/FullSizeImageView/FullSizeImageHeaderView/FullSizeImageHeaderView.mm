#import "FullSizeImageHeaderView.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation FullSizeImageHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSLayoutConstraint* _heightConstraint;
    __weak id<FullSizeImageHeaderViewDelegate> _delegate;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
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
