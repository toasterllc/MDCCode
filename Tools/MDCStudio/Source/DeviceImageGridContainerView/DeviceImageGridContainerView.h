#import <Cocoa/Cocoa.h>
#import "Shared/MDCDevice.h"
#import "ImageSelection.h"
#import "ImageGridContainerView/ImageGridContainerView.h"
@class ImageGridScrollView;

@interface DeviceImageGridContainerView : ImageGridContainerView
- (instancetype)initWithDevice:(MDCStudio::MDCDevicePtr)device
    selection:(MDCStudio::ImageSelectionPtr)selection;

- (NSButton*)configureDeviceButton;
@end
