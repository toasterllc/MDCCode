#import <Cocoa/Cocoa.h>
#import "Image.h"
#import "ImageLibrary.h"
#import "ImageCache.h"

@interface ImageView : NSView
- (instancetype)initWithImageThumb:(const MDCStudio::ImageThumb&)imageThumb
    imageCache:(MDCStudio::ImageCachePtr)imageCache;

- (const MDCStudio::ImageThumb&)imageThumb;
@end
