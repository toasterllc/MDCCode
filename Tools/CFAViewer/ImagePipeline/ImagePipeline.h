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
        Renderer::Buf camRaw_D50;
        Renderer::Buf xyz_D50;
        Renderer::Buf srgb_D65;
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
        
        Renderer::Txt raw = renderer.createTexture(MTLPixelFormatR32Float,
            img.width, img.height);
        
        // Load `raw`
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::LoadRaw", raw,
                // Buffer args
                img.cfaDesc,
                img.width,
                img.height,
                img.pixels
                // Texture args
            );
        }
        
        // Fill `sampleOpts.camRaw_D50`
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::SampleRaw",
                w, h,
                // Buffer args
                img.cfaDesc,
                sampleOpts.rect,
                sampleOpts.camRaw_D50,
                // Texture args
                raw
            );
        }
        
        Renderer::Txt rgb = renderer.createTexture(MTLPixelFormatRGBA32Float,
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
            if (opts.defringe.en) {
                Defringe::Run(renderer, img.cfaDesc, opts.defringe.opts, raw);
            }
            
            // Reconstruct highlights
            if (opts.reconstructHighlights.en) {
                const simd::float3 badPixelFactors = _simdFromMat(opts.reconstructHighlights.badPixelFactors);
                const simd::float3 goodPixelFactors = _simdFromMat(opts.reconstructHighlights.goodPixelFactors);
                
                Renderer::Txt tmp = renderer.createTexture(MTLPixelFormatR32Float,
                    img.width, img.height);
                
                renderer.render("CFAViewer::Shader::ImagePipeline::ReconstructHighlights", tmp,
                    // Buffer args
                    img.cfaDesc,
                    badPixelFactors,
                    goodPixelFactors,
                    // Texture args
                    raw
                );
                raw = std::move(tmp);
            }
            
            // LMMSE Debayer
            {
                DebayerLMMSE::Run(renderer, img.cfaDesc, opts.debayerLMMSE.applyGamma, raw, rgb);
            }
            
            // Camera raw -> XYY.D50
            {
                const simd::float3x3 colorMatrix = _simdFromMat(opts.colorMatrix);
                renderer.render("CFAViewer::Shader::ImagePipeline::XYYD50FromCamRaw", rgb,
                    // Buffer args
                    colorMatrix,
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
                renderer.render("CFAViewer::Shader::ImagePipeline::XYZD50FromXYYD50", rgb,
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
            
            // Fill `sampleOpts.xyz_D50`
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::SampleRGB",
                    w, h,
                    // Buffer args
                    img.cfaDesc,
                    sampleOpts.rect,
                    sampleOpts.xyz_D50,
                    // Texture args
                    rgb
                );
            }
            
            // XYZ.D50 -> LSRGB.D65
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::LSRGBD65FromXYZD50", rgb,
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
            
            // Fill `sampleOpts.srgb_D65`
            {
                renderer.render("CFAViewer::Shader::ImagePipeline::SampleRGB",
                    w, h,
                    // Buffer args
                    img.cfaDesc,
                    sampleOpts.rect,
                    sampleOpts.srgb_D65,
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
