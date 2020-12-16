#import <QuartzCore/QuartzCore.h>
#import "MetalTypes.h"

@interface HistogramLayer : CAMetalLayer
- (void)updateHistogram:(const MetalTypes::Histogram&)histogram;
@end

