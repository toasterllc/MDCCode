#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"

@interface DeviceImageGridHeaderView : NSView
- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device;
- (size_t)loadCount;
@end
