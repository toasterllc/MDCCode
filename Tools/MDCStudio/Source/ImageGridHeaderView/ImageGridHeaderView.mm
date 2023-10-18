#import "ImageGridHeaderView.h"
#import "NibViewInit.h"
using namespace MDCStudio;

@implementation ImageGridHeaderView {
    IBOutlet NSView* _nibView;
    IBOutlet NSLayoutConstraint* _heightConstraint;
    IBOutlet NSTextField* _statusLabel;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NibViewInit(self, _nibView);
    return self;
}

- (NSSize)intrinsicContentSize {
    return { NSViewNoIntrinsicMetric, [_heightConstraint constant] };
}

- (void)setStatus:(NSString*)x {
    [_statusLabel setStringValue:x];
}

@end
