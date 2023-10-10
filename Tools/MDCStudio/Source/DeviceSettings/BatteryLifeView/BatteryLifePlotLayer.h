#import <QuartzCore/QuartzCore.h>
#import "BatteryLifeSimulator.h"

@interface BatteryLifePlotLayer : CAShapeLayer
- (void)setPoints:(std::vector<MDCStudio::BatteryLifeSimulator::Point>)points;
@end
