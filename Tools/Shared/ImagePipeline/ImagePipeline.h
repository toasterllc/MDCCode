#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "../Renderer.h"
#import "../Mat.h"
#import "../Color.h"
#import "Defringe.h"
#import "ImagePipelineTypes.h"

namespace MDCTools::ImagePipeline {

class Pipeline {
public:
    struct RawImage {
        MDCTools::CFADesc cfaDesc;
        size_t width = 0;
        size_t height = 0;
        const ImagePixel* pixels = nullptr;
    };
    
    struct Options {
        bool rawMode = false;
        
        std::optional<MDCTools::Color<MDCTools::ColorSpace::Raw>> illum;
        std::optional<Mat<double,3,3>> colorMatrix;
        
        struct {
            bool en = false;
            Defringe::Options opts;
        } defringe;
        
        struct {
            bool en = false;
        } reconstructHighlights;
        
        struct {
            bool applyGamma = false;
        } debayerLMMSE;
        
        float exposure = 0;
        float saturation = 0;
        float brightness = 0;
        float contrast = 0;
        
        struct {
            bool en = false;
            float amount = 0;
            float radius = 0;
        } localContrast;
        
        SampleRect sampleRect;
    };
    
    struct Result {
        MDCTools::Renderer::Txt txt; // LSRGB colorspace
        MDCTools::Color<MDCTools::ColorSpace::Raw> illum; // Illuminant that was used
        Mat<double,3,3> colorMatrix; // Color matrix that was used
        struct {
            MDCTools::Renderer::Buf raw;
            MDCTools::Renderer::Buf xyzD50;
            MDCTools::Renderer::Buf lsrgb;
        } sampleBufs;
    };
    
    static Result Run(MDCTools::Renderer& renderer, const RawImage& rawImg, const Options& opts);
};

} // namespace MDCTools::ImagePipeline
