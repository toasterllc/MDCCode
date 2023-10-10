#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <vector>
#import "BatteryLifeSimulator.h"

@interface BatteryLifePlotView : NSView
// -setPoints: set the points to be plotted
- (void)setPoints:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)x;
- (CAShapeLayer*)plotLayer;
@end
