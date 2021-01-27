#import <QuartzCore/QuartzCore.h>
#import "ImageLayerTypes.h"
#import "Mat.h"
#import "ColorUtil.h"

@class ImageLayer;
using ImageLayerDataChangedHandler = void(^)(ImageLayer*);

namespace CFAViewer::ImageLayerTypes {
    struct Image {
        uint32_t width = 0;
        uint32_t height = 0;
        CFAViewer::MetalTypes::ImagePixel* pixels = nullptr;
    };
    
    struct ImageAdjustments {
        float exposure = 0;
        float brightness = 0;
        float contrast = 0;
        float saturation = 0;
        
        struct {
            bool enable = false;
            float amount = 0;
            float radius = 0;
        } localContrast;
    };
};

@interface ImageLayer : CAMetalLayer

- (void)setImage:(const CFAViewer::ImageLayerTypes::Image&)image;
- (void)setColorMatrix:(const Mat<double,3,3>&)cm;
- (void)setDebayerLMMSEGammaEnabled:(bool)en;
- (void)setImageAdjustments:(const CFAViewer::ImageLayerTypes::ImageAdjustments&)adj;
- (void)setHighlightFactor:(const Mat<double,3,3>&)hf;
- (void)setSampleRect:(CGRect)rect;
// `handler` is called on a background queue when histograms/sample data changes
- (void)setDataChangedHandler:(ImageLayerDataChangedHandler)handler;

- (CFAViewer::MetalTypes::Histogram)inputHistogram;
- (CFAViewer::MetalTypes::Histogram)outputHistogram;

- (ColorUtil::Color_CamRaw_D50)sample_CamRaw_D50;
- (ColorUtil::Color_XYZ_D50)sample_XYZ_D50;
- (ColorUtil::Color_SRGB_D65)sample_SRGB_D65;

@end
