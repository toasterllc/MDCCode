#import <Cocoa/Cocoa.h>
#import <atomic>
@class ImageExportProgressDialog;

@interface ImageExportProgressDialog : NSObject
- (NSWindow*)window;
- (void)setImageCount:(size_t)x;
- (void)setProgress:(float)x;
- (const std::atomic<bool>&)canceled;
@end
