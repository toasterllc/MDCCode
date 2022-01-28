#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <memory>
#import "Grid.h"
#import "ImageLibrary.h"

@interface ImageGridLayer : CAMetalLayer

- (void)setImageLibrary:(ImageLibraryPtr)imgLib;

- (void)setContainerWidth:(CGFloat)width;
- (CGFloat)containerHeight;

@end
