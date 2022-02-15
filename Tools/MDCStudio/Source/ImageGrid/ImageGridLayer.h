#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <set>
#import "ImageLibrary.h"

using ImageGridLayerImageIds = std::set<Img::Id>;

@interface ImageGridLayer : CAMetalLayer

- (instancetype)initWithImageLibrary:(ImageLibraryPtr)imgLib;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;

- (void)recomputeGrid;

// -setResizingUnderway: is necessary to prevent artifacts when resizing
- (void)setResizingUnderway:(bool)resizing;

- (ImageGridLayerImageIds)imageIdsForRect:(CGRect)rect;
- (void)setSelectedImageIds:(const ImageGridLayerImageIds&)imageIds;

@end
