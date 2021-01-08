#import <QuartzCore/QuartzCore.h>
#import "MetalTypes.h"

@interface HistogramLayer : CAMetalLayer
- (void)setHistogram:(const CFAViewer::MetalTypes::Histogram&)histogram;
- (CGPoint)valueFromPoint:(CGPoint)p; // `p` must be in the receiver's bounds
@end
