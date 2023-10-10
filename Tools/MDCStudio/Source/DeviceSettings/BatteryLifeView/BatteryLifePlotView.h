#import <Cocoa/Cocoa.h>
#import <vector>
#import "BatteryLifeSimulator.h"

@interface BatteryLifePlotView : NSView
- (void)setPointsMin:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)x;
- (void)setPointsMax:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)x;
@end
