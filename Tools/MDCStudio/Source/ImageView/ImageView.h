#import <Cocoa/Cocoa.h>
#import "Image.h"
#import "ImageLibrary.h"
#import "ImageCache.h"

@interface ImageView : NSView
- (instancetype)initWithImageRef:(const MDCStudio::ImageRef&)imageRef
    imageCache:(MDCStudio::ImageCachePtr)cache;

- (const MDCStudio::ImageRef&)imageRef;
@end
