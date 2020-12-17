#import <QuartzCore/QuartzCore.h>
#import "MetalTypes.h"

@interface HistogramLayer : CAMetalLayer
- (void)updateHistogram:(const MetalTypes::Histogram&)histogram;
- (CGPoint)valueFromPoint:(CGPoint)p; // `p` must be in the receiver's bounds
@end
