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
- (instancetype)initWithImageThumb:(const MDCStudio::ImageRecord&)imageThumb
    imageSource:(MDCStudio::ImageSourcePtr)imageSource;

- (const MDCStudio::ImageRecord&)imageThumb;

- (void)setDelegate:(id<ImageViewDelegate>)delegate;

//- (NSView*)initialFirstResponder;

@end

@interface ImageScrollView : FixedScrollView
@end
