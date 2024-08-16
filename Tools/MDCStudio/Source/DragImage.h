#import <Cocoa/Cocoa.h>
#import "ImageSource.h"

@interface DragImage : NSDraggingItem <NSFilePromiseProviderDelegate>

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource
    imageRecord:(MDCStudio::ImageRecordPtr)rec draggingFrame:(CGRect)draggingFrame;

@end
