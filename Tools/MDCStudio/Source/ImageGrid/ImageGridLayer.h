#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <set>
#import "ImageLibrary.h"

using ImageGridLayerImageIds = std::set<Img::Id>;
//using ImageGridLayerIndexes = std::set<size_t>;

@interface ImageGridLayer : CAMetalLayer

- (instancetype)initWithImageLibrary:(ImageLibraryPtr)imgLib;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;
- (size_t)columnCount;
- (void)recomputeGrid;

// -setResizingUnderway: is necessary to prevent artifacts when resizing
- (void)setResizingUnderway:(bool)resizing;

- (ImageGridLayerImageIds)imageIdsForRect:(CGRect)rect;
- (CGRect)rectForImageAtIndex:(size_t)idx;

- (const ImageGridLayerImageIds&)selectedImageIds;
- (void)setSelectedImageIds:(const ImageGridLayerImageIds&)imageIds;

//- (ImageGridLayerIndexes)indexesForRect:(CGRect)rect;
//- (void)setSelectedIndexes:(const ImageGridLayerIndexes&)indexes;

@end
