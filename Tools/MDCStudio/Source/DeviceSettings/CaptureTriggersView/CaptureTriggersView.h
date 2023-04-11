#import <Cocoa/Cocoa.h>
#import "Code/Shared/MSP.h"

@interface CaptureTriggersView : NSView
- (instancetype)initWithEvents:(const MSP::Settings::Events&)events;
- (const MSP::Settings::Events&)events;
@end
