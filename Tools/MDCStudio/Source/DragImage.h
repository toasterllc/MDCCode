#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
@class ImageExportProgressDialog;

@interface DragImage : NSDraggingItem <NSFilePromiseProviderDelegate>

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource
    imageRecord:(MDCStudio::ImageRecordPtr)rec
    progressDialog:(ImageExportProgressDialog*)progressDialog
    operationQueue:(NSOperationQueue*)queue
    draggingFrame:(CGRect)draggingFrame;

@end
