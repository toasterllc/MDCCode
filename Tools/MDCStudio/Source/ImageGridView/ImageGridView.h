#import <Cocoa/Cocoa.h>
#import <set>
#import "ImageSource.h"
#import "Code/Shared/Img.h"
#import "FixedDocumentView.h"
@class ImageGridView;

@protocol ImageGridViewDelegate
- (void)imageGridViewSelectionChanged:(ImageGridView*)imageGridView;
- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView;
@end

@interface ImageGridView : FixedDocumentView

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;

- (void)setDelegate:(id<ImageGridViewDelegate>)delegate;

- (MDCStudio::ImageSourcePtr)imageSource;
- (const MDCStudio::ImageSet&)selection;

- (void)setSortNewestFirst:(bool)sortNewestFirst;

//- (NSView*)initialFirstResponder;

@end

@interface ImageGridScrollView : FixedScrollView
@end
