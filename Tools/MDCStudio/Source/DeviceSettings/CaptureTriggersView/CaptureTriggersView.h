#import <Cocoa/Cocoa.h>
#import "Shared/MSP.h"

@interface CaptureTriggersView : NSView
- (instancetype)initWithTriggers:(const MSP::Triggers&)triggers;
- (const MSP::Triggers&)triggers;
@end
