#import <QuartzCore/QuartzCore.h>
#import "MetalUtil.h"
#import "Mat.h"
#import "ColorUtil.h"
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

//- (void)setHighlightFactor:(const Mat<double,3,3>&)hf;

- (void)setSampleRect:(CGRect)rect;
// `handler` is called on a background queue when histograms/sample data changes
- (void)setDataChangedHandler:(ImageLayerDataChangedHandler)handler;

- (CFAViewer::MetalUtil::Histogram)inputHistogram;
- (CFAViewer::MetalUtil::Histogram)outputHistogram;

- (ColorUtil::Color_CamRaw_D50)sample_CamRaw_D50;
- (ColorUtil::Color_XYZ_D50)sample_XYZ_D50;
- (ColorUtil::Color_SRGB_D65)sample_SRGB_D65;

- (id)CGImage;

@end
