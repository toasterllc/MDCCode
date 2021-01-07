#import <QuartzCore/QuartzCore.h>
#import "ImageLayerTypes.h"
#import "Mat.h"

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
- (void)setColorMatrix:(const Mat<double,3,3>&)cm;
- (void)setHighlightFactor:(const Mat<double,3,3>&)hf;
- (void)setHistogramChangedHandler:(ImageLayerHistogramChangedHandler)histogramChangedHandler;
- (CFAViewer::MetalTypes::Histogram)inputHistogram;
- (CFAViewer::MetalTypes::Histogram)outputHistogram;

- (void)setSampleRect:(CGRect)rect;
- (simd::float3)sampleCameraRaw;
- (simd::float3)sampleXYZD50;
- (simd::float3)sampleSRGBD65;

@end
