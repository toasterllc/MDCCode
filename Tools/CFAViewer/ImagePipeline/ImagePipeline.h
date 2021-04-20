#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "Renderer.h"
#import "Defringe.h"
#import "Mat.h"

namespace CFAViewer::ImagePipeline {

class Pipeline {
public:
    struct Image {
        CFADesc cfaDesc;
        uint32_t width = 0;
        uint32_t height = 0;
        Renderer::Buf pixels;
    };
    
    struct Options {
        bool rawMode = false;
        
        Mat<double,3,1> whiteBalance = { 1.,1.,1. };
        
        struct {
            bool en = false;
            Defringe::Options opts;
        } defringe;
        
        struct {
            bool en = false;
            Mat<double,3,1> badPixelFactors = {1.,1.,1.};
            Mat<double,3,1> goodPixelFactors = {1.,1.,1.};
        } reconstructHighlights;
        
        struct {
            bool applyGamma = false;
        } debayerLMMSE;
        
        Mat<double,3,3> colorMatrix = {
            1.,0.,0.,
            0.,1.,0.,
            0.,0.,1.,
        };
        
        float exposure = 0;
        float brightness = 0;
        float contrast = 0;
        float saturation = 0;
        
        struct {
            bool en = false;
            float amount = 0;
            float radius = 0;
        } localContrast;
    };
    
    struct SampleOptions {
        SampleRect rect;
        Renderer::Buf raw;
        Renderer::Buf xyzD50;
        Renderer::Buf srgb;
    };
    #warning TODO: return resulting texture instead?
    static void Run(Renderer& renderer, const Image& img, const Options& opts,
        const SampleOptions& sampleOpts, id<MTLTexture> outTxt
    );
};

} // namespace CFAViewer::ImagePipeline
