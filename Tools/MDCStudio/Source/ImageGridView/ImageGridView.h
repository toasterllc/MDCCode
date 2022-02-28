#import <Cocoa/Cocoa.h>
#import <set>
#import "ImageSource.h"
@class ImageGridView;

using ImageGridViewImageIds = std::set<MDCStudio::ImageId>;

@protocol ImageGridViewDelegate
- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView;
@end

@interface ImageGridView : NSView

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;

- (void)setDelegate:(id<ImageGridViewDelegate>)delegate;

- (MDCStudio::ImageSourcePtr)imageSource;
- (const ImageGridViewImageIds&)selectedImageIds;

- (NSView*)initialFirstResponder;

@end
