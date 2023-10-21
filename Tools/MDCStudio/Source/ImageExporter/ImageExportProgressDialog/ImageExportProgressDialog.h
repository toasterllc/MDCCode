#import <Cocoa/Cocoa.h>
@class ImageExportProgressDialog;

@protocol ImageExportProgressDialogDelegate
@required
- (void)imageExportProgressDialogCancelled:(ImageExportProgressDialog*)x;
@end

@interface ImageExportProgressDialog : NSWindow
- (void)setProgress:(float)x;
- (void)setDelegate:(id<ImageExportProgressDialogDelegate>)x;
@end
