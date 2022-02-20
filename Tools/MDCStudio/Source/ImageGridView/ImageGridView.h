#import <Cocoa/Cocoa.h>
#import <set>
#import "ImageLibrary.h"
@class ImageGridView;

using ImageGridViewImageIds = std::set<MDCStudio::ImageId>;
using ImageGridViewOpenImageHandler = void(^)(ImageGridView*);

@interface ImageGridView : NSView

- (instancetype)initWithImageLibrary:(MDCStudio::ImageLibraryPtr)imgLib;

// -setResizingUnderway: is necessary to prevent artifacts when resizing
- (void)setResizingUnderway:(bool)resizing;

- (void)setOpenImageHandler:(ImageGridViewOpenImageHandler)handler;

- (MDCStudio::ImageLibraryPtr)imageLibrary;
- (const ImageGridViewImageIds&)selectedImageIds;

@end
