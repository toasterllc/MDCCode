#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageGridView/ImageGridView.h"
@class DeviceImageGridHeaderView;

@interface DeviceImageGridScrollView : ImageGridScrollView
- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device;
- (ImageGridView*)imageGridView;
- (DeviceImageGridHeaderView*)headerView;
@end
