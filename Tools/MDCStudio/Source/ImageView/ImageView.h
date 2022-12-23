#import <Cocoa/Cocoa.h>
#import "Image.h"
#import "ImageSource.h"
#import "FixedDocumentView.h"
@class ImageView;

@protocol ImageViewDelegate
@required
- (void)imageViewPreviousImage:(ImageView*)imageView;
- (void)imageViewNextImage:(ImageView*)imageView;
@end

@interface ImageView : FixedDocumentView
- (instancetype)initWithImageThumb:(const MDCStudio::ImageThumb&)imageThumb
    imageSource:(MDCStudio::ImageSourcePtr)imageSource;

- (const MDCStudio::ImageThumb&)imageThumb;

- (void)setDelegate:(id<ImageViewDelegate>)delegate;

//- (NSView*)initialFirstResponder;

@end
