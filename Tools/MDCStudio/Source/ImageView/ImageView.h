#import <Cocoa/Cocoa.h>
#import "Image.h"
#import "ImageLibrary.h"
#import "ImageCache.h"
@class ImageView;

@protocol ImageViewDelegate
@required
- (void)imageViewPreviousImage:(ImageView*)imageView;
- (void)imageViewNextImage:(ImageView*)imageView;
@end

@interface ImageView : NSView
- (instancetype)initWithImageThumb:(const MDCStudio::ImageThumb&)imageThumb
    imageCache:(MDCStudio::ImageCachePtr)imageCache;

- (const MDCStudio::ImageThumb&)imageThumb;

- (void)setDelegate:(id<ImageViewDelegate>)delegate;
@end
