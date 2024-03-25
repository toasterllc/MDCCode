#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "../Mat.h"
#import "../Color.h"
#import "Defringe.h"
#import "ImagePipelineTypes.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"

namespace MDCTools::ImagePipeline {

using ColorRaw = MDCTools::Color<MDCTools::ColorSpace::Raw>;
using ColorMatrix = Mat<double,3,3>;

class Pipeline {
public:
//    struct DebayerOptions {
//        MDCTools::CFADesc cfaDesc;
//        ColorRaw illum;
//        
//        struct {
//            bool en = false;
//            Defringe::Options opts;
//        } defringe;
//        
//        struct {
//            bool en = false;
//        } reconstructHighlights;
//        
//        struct {
//            bool applyGamma = false;
//        } debayerLMMSE;
//    };
//    
//    struct DebayerResult {
//        ColorRaw illum; // Illuminant that was used
//    };
    
    struct TimestampOptions {
        std::string string;
        simd::float2 position; // [0,1] Cartesion
    };
    
    struct Options {
        MDCTools::CFADesc cfaDesc;
        
        std::optional<ColorRaw> illum;
        std::optional<ColorMatrix> colorMatrix;
        
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
            float amount = 0;
            float radius = 0;
        } localContrast;
        
        TimestampOptions timestamp;
    };
    
    static Toastbox::Renderer::Txt TextureForRaw(Toastbox::Renderer& renderer, size_t width, size_t height, const ImagePixel* pixels) {
        constexpr size_t SamplesPerPixel = 1;
        constexpr size_t BytesPerSample = sizeof(*pixels);
        Toastbox::Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, width, height);
        renderer.textureWrite(raw, pixels, SamplesPerPixel, BytesPerSample, ImagePixelMax);
        return raw;
    }
    
//    static ColorRaw IlluminantEstimate(const ColorRaw& illum);
//    static ColorMatrix ColorMatrixForIlluminant(const ColorRaw& illum);
    
//    static Color<ColorSpace::Raw> EstimateIlluminant(Toastbox::Renderer& renderer, const MDCTools::CFADesc& cfaDesc, id<MTLTexture> srcRaw);
    static void Run(Toastbox::Renderer& renderer, const Options& opts, id<MTLTexture> srcRaw, id<MTLTexture> dstRgb);
    
    static void TimestampOverlayRender(Toastbox::Renderer& renderer,
        const TimestampOptions& opts, id<MTLTexture> txt);
};

} // namespace MDCTools::ImagePipeline
