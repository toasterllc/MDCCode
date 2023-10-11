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
- (void)setSelection:(MDCStudio::ImageSet)selection;

- (CGRect)rectForImageIndex:(size_t)idx;
- (CGRect)rectForImageRecord:(MDCStudio::ImageRecordPtr)rec;
- (void)scrollToImageRect:(CGRect)rect center:(bool)center;

- (void)setSortNewestFirst:(bool)x;

//- (NSView*)initialFirstResponder;

@end

@interface ImageGridScrollView : FixedScrollView
- (NSView*)headerView;
- (void)setHeaderView:(NSView*)x;
@end
