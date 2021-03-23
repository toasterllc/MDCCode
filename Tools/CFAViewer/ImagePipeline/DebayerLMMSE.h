#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "MetalUtil.h"
#import "ImagePipelineTypes.h"

namespace CFAViewer::ImagePipeline {
    class DebayerLMMSE {
    public:
        static void Run(Renderer& renderer, const CFADesc& cfaDesc, bool applyGamma,
            id<MTLTexture> rawOriginal, id<MTLTexture> rgb) {
            
            const NSUInteger w = [rawOriginal width];
            const NSUInteger h = [rawOriginal height];
            
            Renderer::Txt raw = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            
            // Copy `rawOriginal` so we can modify it
            renderer.copy(rawOriginal, raw);
            
            // Gamma before (improves quality of edges)
            if (applyGamma) {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::GammaForward", raw,
                    // Texture args
                    raw
                );
            }
            
            // Horizontal interpolation
            Renderer::Txt filteredHTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            {
                const bool h = true;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::Interp5", filteredHTxt,
                    // Buffer args
                    h,
                    // Texture args
                    raw
                );
            }
            
            // Vertical interpolation
            Renderer::Txt filteredVTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            {
                const bool h = false;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::Interp5", filteredVTxt,
                    // Buffer args
                    h,
                    // Texture args
                    raw
                );
            }
            
            // Calculate DiffH
            Renderer::Txt diffHTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::NoiseEst", diffHTxt,
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    filteredHTxt
                );
            }
            
            // Calculate DiffV
            Renderer::Txt diffVTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::NoiseEst", diffVTxt,
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    filteredVTxt
                );
            }
            
            // Smooth DiffH
            {
                const bool h = true;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::Smooth9", filteredHTxt,
                    // Buffer args
                    h,
                    // Texture args
                    diffHTxt
                );
            }
            
            // Smooth DiffV
            {
                const bool h = false;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::Smooth9", filteredVTxt,
                    // Buffer args
                    h,
                    // Texture args
                    diffVTxt
                );
            }
            
            // Calculate rgb.g
            {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcG", rgb,
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    filteredHTxt,
                    diffHTxt,
                    filteredVTxt,
                    diffVTxt
                );
            }
            
            // Calculate diffGRTxt.r
            Renderer::Txt diffGRTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            {
                const bool modeGR = true;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcDiffGRGB", diffGRTxt,
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    rgb
                );
            }
            
            // Calculate diffGBTxt.b
            Renderer::Txt diffGBTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            {
                const bool modeGR = false;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcDiffGRGB", diffGBTxt,
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    rgb
                );
            }
            
            // Calculate diffGRTxt.b
            {
                const bool modeGR = true;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcDiagAvgDiffGRGB", diffGRTxt,
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    rgb,
                    diffGRTxt
                );
            }
            
            // Calculate diffGBTxt.r
            {
                const bool modeGR = false;
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcDiagAvgDiffGRGB", diffGBTxt,
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    rgb,
                    diffGBTxt
                );
            }
            
            // Calculate diffGRTxt.g
            {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcAxialAvgDiffGRGB", diffGRTxt,
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    rgb,
                    diffGRTxt
                );
            }
            
            // Calculate diffGBTxt.g
            {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcAxialAvgDiffGRGB", diffGBTxt,
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    rgb,
                    diffGBTxt
                );
            }
            
            // Calculate rgb.rb
            {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::CalcRB", rgb,
                    // Texture args
                    rgb,
                    diffGRTxt,
                    diffGBTxt
                );
            }
            
            // Gamma after (improves quality of edges)
            if (applyGamma) {
                renderer.render("CFAViewer::Shader::DebayerLMMSE::GammaReverse", rgb,
                    // Texture args
                    rgb
                );
            }
        }
    };
};
