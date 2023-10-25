#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageGridView/ImageGridView.h"
@class DeviceImageGridHeaderView;

@interface DeviceImageGridScrollView : ImageGridScrollView
- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device
    selection:(MDCStudio::ImageSelectionPtr)selection;

- (NSButton*)configureDeviceButton;
@end
