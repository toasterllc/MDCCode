#import <Cocoa/Cocoa.h>
#import <chrono>
#import "BatteryLifeEstimate.h"

@interface BatteryLifePlotView : NSView
- (void)setPoints:(std::vector<MDCStudio::BatteryLifeEstimate::Point>)points;
@end
