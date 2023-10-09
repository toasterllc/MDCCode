#import <QuartzCore/QuartzCore.h>
#import "BatteryLifeEstimate.h"

@interface BatteryLifePlotLayer : CAShapeLayer
- (void)setPoints:(std::vector<MDCStudio::BatteryLifeEstimate::Point>)points;
@end
