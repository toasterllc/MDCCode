#import <Cocoa/Cocoa.h>
#import <atomic>
@class ImageExportProgressDialog;

@interface ImageExportProgressDialog : NSObject
- (instancetype)initWithParentWindow:(NSWindow*)parentWindow imageCount:(size_t)imageCount;
- (void)incrementProgress;
- (bool)canceled;
@end
