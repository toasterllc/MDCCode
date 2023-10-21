#import <Cocoa/Cocoa.h>
@class ImageExportProgressDialog;

using ImageExportProgressDialogHandler = void(^)(ImageExportProgressDialog*);

@interface ImageExportProgressDialog : NSObject
- (NSWindow*)window;
- (void)setImageCount:(size_t)x;
- (void)setProgress:(float)x;
- (void)setCancelHandler:(ImageExportProgressDialogHandler)x;
@end
