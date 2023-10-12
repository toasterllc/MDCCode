#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageGridHeaderView/ImageGridHeaderView.h"
@class DeviceImageGridHeaderView;

@protocol DeviceImageGridHeaderViewDelegate
@required
- (void)deviceImageGridHeaderViewLoad:(DeviceImageGridHeaderView*)x;
@end

@interface DeviceImageGridHeaderView : ImageGridHeaderView
- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device;
- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x;
@end
