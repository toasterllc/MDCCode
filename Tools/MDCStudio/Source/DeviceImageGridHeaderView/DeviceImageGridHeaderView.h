#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
@class DeviceImageGridHeaderView;

@protocol DeviceImageGridHeaderViewDelegate
@required
- (void)deviceImageGridHeaderViewLoad:(DeviceImageGridHeaderView*)x;
@end

@interface DeviceImageGridHeaderView : NSView
- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device;
- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x;
@end
