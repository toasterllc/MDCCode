#import <QuartzCore/QuartzCore.h>
#import "ImageLayerTypes.h"

@class ImageLayer;
using ImageLayerHistogramChangedHandler = void(^)(ImageLayer*);

namespace CFAViewer::ImageLayerTypes {
    struct Image {
        uint32_t width = 0;
        uint32_t height = 0;
        CFAViewer::MetalTypes::ImagePixel* pixels = nullptr;
    };
};

@interface ImageLayer : CAMetalLayer
- (void)updateImage:(const CFAViewer::ImageLayerTypes::Image&)image;
- (void)updateColorMatrix:(const simd::float3x3&)colorMatrix;
- (void)setHistogramChangedHandler:(ImageLayerHistogramChangedHandler)histogramChangedHandler;
- (CFAViewer::MetalTypes::Histogram)inputHistogram;
- (CFAViewer::MetalTypes::Histogram)outputHistogram;
@end
