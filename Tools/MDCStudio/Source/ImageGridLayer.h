#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <memory>
#import "Grid.h"
#import "ImgStore.h"

@interface ImageGridLayer : CAMetalLayer

- (void)setImgStore:(ImgStorePtr)imgStore;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;

@end
