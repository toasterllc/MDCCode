#import <Cocoa/Cocoa.h>
#import "BaseView.h"
@class HistogramLayer;

@interface HistogramView : BaseView
- (HistogramLayer*)histogramLayer;
@end
