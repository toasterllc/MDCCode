#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "../Renderer.h"
#import "../Mat.h"
#import "../Color.h"
#import "Defringe.h"
#import "ImagePipelineTypes.h"

namespace MDCTools::ImagePipeline {

using ColorRaw = MDCTools::Color<MDCTools::ColorSpace::Raw>;
using ColorMatrix = Mat<double,3,3>;

class Pipeline {
public:
    struct DebayerOptions {
        MDCTools::CFADesc cfaDesc;
        
        struct {
            bool en = false;
            Defringe::Options opts;
        } defringe;
        
        struct {
            bool en = false;
            ColorRaw illum;
        } reconstructHighlights;
        
        struct {
            bool applyGamma = false;
        } debayerLMMSE;
    };
    
//    struct DebayerResult {
//        ColorRaw illum; // Illuminant that was used
//    };
    
    struct ProcessOptions {
        std::optional<ColorRaw> illum;
        std::optional<ColorMatrix> colorMatrix;
        
        float exposure = 0;
        float saturation = 0;
        float brightness = 0;
        float contrast = 0;
        
        struct {
            bool en = false;
            float amount = 0;
            float radius = 0;
        } localContrast;
    };
    
    static Renderer::Txt TextureForRaw(MDCTools::Renderer& renderer, size_t width, size_t height, const ImagePixel* pixels) {
        constexpr size_t SamplesPerPixel = 1;
        constexpr size_t BytesPerSample = sizeof(*pixels);
        Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, width, height);
        renderer.textureWrite(raw, pixels, SamplesPerPixel, BytesPerSample, ImagePixelMax);
        return raw;
    }
    
//    static ColorRaw IlluminantEstimate(const ColorRaw& illum);
//    static ColorMatrix ColorMatrixForIlluminant(const ColorRaw& illum);
    
//    static Color<ColorSpace::Raw> EstimateIlluminant(MDCTools::Renderer& renderer, const MDCTools::CFADesc& cfaDesc, id<MTLTexture> srcRaw);
    static void Debayer(MDCTools::Renderer& renderer, const DebayerOptions& opts, id<MTLTexture> srcRaw, id<MTLTexture> dstRgb);
    static void Process(MDCTools::Renderer& renderer, const ProcessOptions& opts, id<MTLTexture> srcRgb, id<MTLTexture> dstRgb);
};

} // namespace MDCTools::ImagePipeline
