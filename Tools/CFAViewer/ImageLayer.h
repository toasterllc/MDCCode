#import <QuartzCore/QuartzCore.h>
#import "ImageLayerTypes.h"

@class ImageLayer;
using ImageLayerHistogramChangedHandler = void(^)(ImageLayer*);

namespace ImageLayerTypes {
    struct Image {
        uint32_t width = 0;
        uint32_t height = 0;
        MetalTypes::ImagePixel* pixels = nullptr;
    };
};

@interface ImageLayer : CAMetalLayer
- (void)updateImage:(const ImageLayerTypes::Image&)image;
- (void)updateColorMatrix:(const MetalTypes::ColorMatrix&)colorMatrix;
- (void)setHistogramChangedHandler:(ImageLayerHistogramChangedHandler)histogramChangedHandler;
- (MetalTypes::Histogram)inputHistogram;
- (MetalTypes::Histogram)outputHistogram;
@end
