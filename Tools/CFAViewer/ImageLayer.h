#import <QuartzCore/QuartzCore.h>
#import "MetalUtil.h"
#import "Mat.h"
#import "Color.h"
#import "ImagePipelineTypes.h"
#import "ImagePipeline.h"

@class ImageLayer;
using ImageLayerDataChangedHandler = void(^)(ImageLayer*);

namespace CFAViewer::ImageLayerTypes {
    struct Image {
        ImagePipeline::CFADesc cfaDesc;
        uint32_t width = 0;
        uint32_t height = 0;
        MetalUtil::ImagePixel* pixels = nullptr;
    };
    
    using Options = CFAViewer::ImagePipeline::Pipeline::Options;
}

@interface ImageLayer : CAMetalLayer

- (void)setImage:(const CFAViewer::ImageLayerTypes::Image&)img;
- (void)setOptions:(const CFAViewer::ImageLayerTypes::Options&)opts;

- (void)setSampleRect:(CGRect)rect;
// `handler` is called on a background queue when histograms/sample data changes
- (void)setDataChangedHandler:(ImageLayerDataChangedHandler)handler;

- (CFAViewer::MetalUtil::Histogram)inputHistogram;
- (CFAViewer::MetalUtil::Histogram)outputHistogram;

- (Color<ColorSpace::Raw>)sampleRaw;
- (Color<ColorSpace::XYZD50>)sampleXYZD50;
- (Color<ColorSpace::SRGB>)sampleSRGB;

- (id)CGImage;

@end
