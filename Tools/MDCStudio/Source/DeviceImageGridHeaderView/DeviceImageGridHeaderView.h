#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
#import "ImageGridHeaderView/ImageGridHeaderView.h"
@class DeviceImageGridHeaderView;

@protocol DeviceImageGridHeaderViewDelegate
@required
- (void)deviceImageGridHeaderViewLoad:(DeviceImageGridHeaderView*)x;
@end

@interface DeviceImageGridHeaderView : ImageGridHeaderView
- (void)setDelegate:(id<DeviceImageGridHeaderViewDelegate>)x;
- (void)setLoadCount:(size_t)x;
- (void)setProgress:(float)x;
@end
