#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"
@class FullSizeImageHeaderView;

@protocol FullSizeImageHeaderViewDelegate
@required
- (void)imageHeaderViewBack:(FullSizeImageHeaderView*)x;
@end

@interface FullSizeImageHeaderView : NSView
- (void)setDelegate:(id<FullSizeImageHeaderViewDelegate>)x;
@end
