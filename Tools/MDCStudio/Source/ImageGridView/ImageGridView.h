#import <Cocoa/Cocoa.h>
#import <set>
#import "ImageLibrary.h"
@class ImageGridView;

using ImageGridViewImageIds = std::set<MDCStudio::ImageId>;

@protocol ImageGridViewDelegate
- (void)imageGridViewOpenSelectedImage:(ImageGridView*)imageGridView;
@end

@interface ImageGridView : NSView

- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib;

// -setResizingUnderway: is necessary to prevent artifacts when resizing
- (void)setResizingUnderway:(bool)resizing;

- (void)setDelegate:(id<ImageGridViewDelegate>)delegate;

- (MDCStudio::ImageLibraryPtr)imageLibrary;
- (const ImageGridViewImageIds&)selectedImageIds;

@end
