#import <Cocoa/Cocoa.h>
#import "ImageSource.h"
#import "FixedDocumentView.h"
@class ImageView;

@protocol ImageViewDelegate
@required
- (void)imageViewPreviousImage:(ImageView*)imageView;
- (void)imageViewNextImage:(ImageView*)imageView;
@end

@interface ImageView : FixedDocumentView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;

- (MDCStudio::ImageRecordPtr)imageRecord;
- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec;

- (void)setDelegate:(id<ImageViewDelegate>)delegate;

//- (NSView*)initialFirstResponder;

@end

@interface ImageScrollView : FixedScrollView
@end
