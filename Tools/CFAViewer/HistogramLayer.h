#import <QuartzCore/QuartzCore.h>
#import "MetalUtil.h"

@interface HistogramLayer : CAMetalLayer
- (void)setHistogram:(const CFAViewer::MetalUtil::Histogram&)histogram;
- (CGPoint)valueFromPoint:(CGPoint)p; // `p` must be in the receiver's bounds
@end
