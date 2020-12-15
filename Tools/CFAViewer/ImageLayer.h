#import <QuartzCore/QuartzCore.h>
#import "ImageLayerTypes.h"

namespace ImageLayerTypes {
    struct Image {
        uint32_t width = 0;
        uint32_t height = 0;
        ImagePixel* pixels = nullptr;
    };
};

@interface ImageLayer : CAMetalLayer
- (void)updateImage:(const ImageLayerTypes::Image&)image;
- (void)updateColorMatrix:(const ImageLayerTypes::ColorMatrix&)colorMatrix;
@end
