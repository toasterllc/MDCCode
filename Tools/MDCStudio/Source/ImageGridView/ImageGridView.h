#import <Cocoa/Cocoa.h>
#import <set>
#import <optional>
#import "ImageSource.h"
#import "ImageSelection.h"
#import "Code/Shared/Img.h"
#import "Code/Lib/AnchoredScrollView/AnchoredDocumentView.h"
@class ImageGridView;

@protocol ImageGridViewResponder
@optional
- (void)_showImage:(id)sender;
@end

@interface ImageGridView : AnchoredDocumentView

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource
    selection:(MDCStudio::ImageSelectionPtr)selection;
- (MDCStudio::ImageSourcePtr)imageSource;

- (CGRect)rectForImageIndex:(size_t)idx;
- (std::optional<CGRect>)rectForImageRecord:(MDCStudio::ImageRecordPtr)rec;
- (void)scrollToImageRect:(CGRect)rect center:(bool)center;

- (void)setSortNewestFirst:(bool)x;

//- (NSView*)initialFirstResponder;

@end

@interface ImageGridScrollView : AnchoredScrollView
- (NSView*)headerView;
- (void)setHeaderView:(NSView*)x;
@end
