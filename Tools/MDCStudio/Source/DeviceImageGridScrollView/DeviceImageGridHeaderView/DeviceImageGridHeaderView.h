#import <Cocoa/Cocoa.h>
#import "MDCDevice.h"

@interface DeviceImageGridHeaderView : NSView
- (void)setStatus:(NSString*)x;
- (void)setLoadCount:(size_t)x;
- (NSButton*)loadButton;
- (void)setProgress:(float)x;
@end
