#import <Cocoa/Cocoa.h>
@class ImageExportProgressDialog;

@interface ImageExportProgressDialog : NSObject
- (NSWindow*)window;
- (void)setImageCount:(size_t)x;
- (void)setProgress:(float)x;
@end
