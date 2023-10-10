#import <Cocoa/Cocoa.h>
#import <vector>
#import "BatteryLifeSimulator.h"

@interface BatteryLifePlotView : NSView
// -setPointsMin: / -setPointsMax: set the minimum/maximum battery life
// points that are to be plotted
- (void)setPointsMin:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)x;
- (void)setPointsMax:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)x;

// minEndX: returns the X coordinate of the end of the minimum battery life plot
- (CGFloat)minEndX;
@end
