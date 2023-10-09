#import <Cocoa/Cocoa.h>
#import <chrono>
#import "Code/Shared/MSP.h"
@class BatteryLifeView;

@protocol BatteryLifeViewDelegate
@required
- (void)batteryLifeViewChanged:(BatteryLifeView*)view;
@end

namespace BatteryLifeViewTypes {

struct BatteryLifeEstimate {
    std::chrono::seconds min;
    std::chrono::seconds max;
};

} // BatteryLifeViewTypes;

@interface BatteryLifeView : NSView
- (instancetype)initWithFrame:(NSRect)frame;
- (void)setDelegate:(id<BatteryLifeViewDelegate>)delegate;
- (void)setTriggers:(const MSP::Triggers&)triggers;
- (BatteryLifeViewTypes::BatteryLifeEstimate)batteryLifeEstimate;
@end
