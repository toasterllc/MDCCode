#import <Cocoa/Cocoa.h>
#import <set>
#import "ImageSource.h"
#import "Code/Shared/Img.h"
#import "FixedDocumentView.h"
@class ImageGridView;

using ImageGridViewImageIds = std::set<Img::Id>;

@protocol ImageGridViewDelegate
- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView;
@end

@interface ImageGridView : FixedDocumentView

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;

- (void)setDelegate:(id<ImageGridViewDelegate>)delegate;

- (MDCStudio::ImageSourcePtr)imageSource;
- (const ImageGridViewImageIds&)selectedImageIds;

//- (NSView*)initialFirstResponder;

@end
