#import "FullSizeImageHeaderView.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation FullSizeImageHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSButton* _backButton;
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

- (void)mouseDown:(NSEvent*)event {
    [[self window] performWindowDragWithEvent:event];
}

- (void)setDelegate:(id<FullSizeImageHeaderViewDelegate>)x {
    _delegate = x;
}

- (IBAction)actionBack:(id)sender {
    [_delegate imageHeaderViewBack:self];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSView* contentView = [[self window] contentView];
    if (!contentView) return;
    NSLayoutConstraint* windowLeftMin = [NSLayoutConstraint constraintWithItem:_backButton
        attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationGreaterThanOrEqual
        toItem:contentView attribute:NSLayoutAttributeLeft multiplier:1 constant:65];
    [windowLeftMin setActive:true];
}

@end
