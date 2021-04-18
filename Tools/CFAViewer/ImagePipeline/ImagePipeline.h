#import <Metal/Metal.h>
#import "MetalUtil.h"
#import "Renderer.h"
#import "ImagePipelineTypes.h"
#import "Defringe.h"
#import "DebayerLMMSE.h"
#import "LocalContrast.h"
#import "Saturation.h"
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
    
    static void Run(
        Renderer& renderer,
        const Image& img,
        const Options& opts,
        const SampleOptions& sampleOpts,
        id<MTLTexture> outTxt
    ) {
        const uint32_t w = img.width;
        const uint32_t h = img.height;
        
        Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float,
            img.width, img.height);
        
        // Load `raw`
        {
            const size_t samplesPerPixel = 1;
            const size_t bytesPerSample = sizeof(MetalUtil::ImagePixel);
            renderer.textureWrite(raw, img.pixels, samplesPerPixel, bytesPerSample, MetalUtil::ImagePixelMax);
        }
        
        // Sample: fill `sampleOpts.raw`
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::SampleRaw",
                w, h,
                // Buffer args
                img.cfaDesc,
                sampleOpts.rect,
                sampleOpts.raw,
                // Texture args
                raw
            );
        }
        
        Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float,
            img.width, img.height);
        
        // Raw mode (bilinear debayer only)
        if (opts.rawMode) {
            // De-bayer
            renderer.render("CFAViewer::Shader::DebayerBilinear::Debayer", rgb,
                // Buffer args
                img.cfaDesc,
                // Texture args
                raw
            );
        
        } else {
            // Reconstruct highlights
            if (opts.reconstructHighlights.en) {
                Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float, img.width/2, img.height/2);
                renderer.render("CFAViewer::Shader::ReconstructHighlights::DebayerDownsample", rgb,
                    // Buffer args
                    img.cfaDesc,
                    // Texture args
                    raw
                );
                
                Renderer::Txt thresh = renderer.textureCreate(MTLPixelFormatR32Float, img.width/2, img.height/2);
                {
                    const simd::float3 scale = {1.179, 0.649, 1.180};
    //                const simd::float3 debugFactors = _simdFromMat(opts.reconstructHighlights.badPixelFactors);
                    renderer.render("CFAViewer::Shader::ReconstructHighlights::Normalize", thresh,
                        // Buffer args
                        scale,
                        // Texture args
                        rgb
                    );
                }
                
//                for (int i=0; i<3; i++) {
//                    Renderer::Txt tmp = renderer.textureCreate(thresh);
//                    renderer.render("CFAViewer::Shader::ReconstructHighlights::ExpandHighlights", tmp,
//                        // Texture args
//                        thresh
//                    );
//                    thresh = std::move(tmp);
//                }
                
                const Mat<double,3,1> illum(1/opts.whiteBalance[0], 1/opts.whiteBalance[1], 1/opts.whiteBalance[2]);
                const double illumMin = std::min(std::min(illum[0], illum[1]), illum[2]);
                const double illumMax = std::max(std::max(illum[0], illum[1]), illum[2]);
                const simd::float3 simdIllum = _simdFromMat(illum);
                const simd::float3 simdIllumMax1 = _simdFromMat(illum/illumMax);
                const simd::float3 simdIllumMin1 = _simdFromMat(illum/illumMin);
                
                const float cutoff = 0.7741562512;//opts.reconstructHighlights.badPixelFactors[0];
                Renderer::Txt highlightMap = renderer.textureCreate(MTLPixelFormatRG32Float, img.width, img.height);
                renderer.render("CFAViewer::Shader::ReconstructHighlights::CreateHighlightMap", highlightMap,
                    // Buffer args
                    cutoff,
                    simdIllumMin1,
                    // Texture args
                    rgb,
                    thresh
                );
                
                for (int i=0; i<1; i++) {
                    Renderer::Txt tmp = renderer.textureCreate(highlightMap);
                    renderer.render("CFAViewer::Shader::ReconstructHighlights::Blur", tmp,
                        // Texture args
                        highlightMap
                    );
                    highlightMap = std::move(tmp);
                }
                
                renderer.render("CFAViewer::Shader::ReconstructHighlights::ReconstructHighlights", raw,
                    // Buffer args
                    img.cfaDesc,
                    simdIllumMin1,
                    // Texture args
                    raw,
                    rgb,
                    highlightMap
                );
            }
            
            // Sample: fill `sampleOpts.xyzD50`
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::SampleRaw",
                    w, h,
                    // Buffer args
                    img.cfaDesc,
                    sampleOpts.rect,
                    sampleOpts.xyzD50,
                    // Texture args
                    raw
                );
            }
            
            // White balance
            {
                const simd::float3 whiteBalance = _simdFromMat(opts.whiteBalance);
                renderer.render("CFAViewer::Shader::ImagePipeline::WhiteBalance", raw,
                    // Buffer args
                    img.cfaDesc,
                    whiteBalance,
                    // Texture args
                    raw
                );
            }
            
            if (opts.defringe.en) {
                Defringe::Run(renderer, img.cfaDesc, opts.defringe.opts, raw);
            }
            
            // LMMSE Debayer
            {
                DebayerLMMSE::Run(renderer, img.cfaDesc, opts.debayerLMMSE.applyGamma, raw, rgb);
            }
            
            // Camera raw -> ProPhotoRGB
            {
                const simd::float3x3 colorMatrix = _simdFromMat(opts.colorMatrix);
                renderer.render("CFAViewer::Shader::ImagePipeline::ApplyColorMatrix", rgb,
                    // Buffer args
                    colorMatrix,
                    // Texture args
                    rgb
                );
            }
            
            // ProPhotoRGB -> XYZ.D50
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::XYZD50FromProPhotoRGB", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // XYZ.D50 -> XYY.D50
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::XYYFromXYZ", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // Exposure
            {
                const float exposure = pow(2, opts.exposure);
                renderer.render("CFAViewer::Shader::ImagePipeline::Exposure", rgb,
                    // Buffer args
                    exposure,
                    // Texture args
                    rgb
                );
            }
            
            // XYY.D50 -> XYZ.D50
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::XYZFromXYY", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // XYZ.D50 -> Lab.D50
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::LabD50FromXYZD50", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // Brightness
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::Brightness", rgb,
                    // Buffer args
                    opts.brightness,
                    // Texture args
                    rgb
                );
            }
            
            // Contrast
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::Contrast", rgb,
                    // Buffer args
                    opts.contrast,
                    // Texture args
                    rgb
                );
            }
            
            // Local contrast
            if (opts.localContrast.en) {
                LocalContrast::Run(renderer, opts.localContrast.amount,
                    opts.localContrast.radius, rgb);
            }
            
            // Lab.D50 -> XYZ.D50
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::XYZD50FromLabD50", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // Saturation
            Saturation::Run(renderer, opts.saturation, rgb);
            
//            // Sample: fill `sampleOpts.xyzD50`
//            {
//                renderer.render("CFAViewer::Shader::ImagePipeline::SampleRGB",
//                    w, h,
//                    // Buffer args
//                    img.cfaDesc,
//                    sampleOpts.rect,
//                    sampleOpts.xyzD50,
//                    // Texture args
//                    rgb
//                );
//            }
            
            // XYZ.D50 -> XYZ.D65
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::BradfordXYZD65FromXYZD50", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // XYZ.D65 -> LSRGB.D65
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::LSRGBD65FromXYZD65", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // Apply SRGB gamma
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::SRGBGamma", rgb,
                    // Texture args
                    rgb
                );
            }
            
            // Sample: fill `sampleOpts.srgb`
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::SampleRGB",
                    w, h,
                    // Buffer args
                    img.cfaDesc,
                    sampleOpts.rect,
                    sampleOpts.srgb,
                    // Texture args
                    rgb
                );
            }
        }
        
        // Final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
        renderer.render("CFAViewer::Shader::ImagePipeline::Display", outTxt,
            // Texture args
            rgb
        );
    }
    
private:
    static simd::float3 _simdFromMat(const Mat<double,3,1>& m) {
        return {
            simd::float3{(float)m[0], (float)m[1], (float)m[2]},
        };
    }
    
    static simd::float3x3 _simdFromMat(const Mat<double,3,3>& m) {
        return {
            simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
            simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
            simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
        };
    }
};

} // namespace CFAViewer::ImagePipeline
