#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
@class ImageHeaderView;

@protocol ImageHeaderViewDelegate
@required
- (void)imageHeaderViewBack:(ImageHeaderView*)x;
@end

@interface ImageHeaderView : NSView
- (void)setDelegate:(id<ImageHeaderViewDelegate>)x;
@end
