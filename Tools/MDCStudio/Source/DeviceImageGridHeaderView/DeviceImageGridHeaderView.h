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
- (void)setLoadCount:(NSUInteger)x;
- (void)setStatus:(NSString*)x;
@end
