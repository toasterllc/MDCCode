#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "MetalUtil.h"
#import "ImageFilter.h"
#import "Renderer.h"

namespace CFAViewer {
    class DebayerLMMSE : public ImageFilter {
    public:
        using ImageFilter::ImageFilter;
        
        struct Options {
            CFADesc cfaDesc;
            bool applyGamma = false;
        };
        
        void run(const Options& opts, id<MTLTexture> rawOriginal, id<MTLTexture> rgb) {
            const NSUInteger w = [rawOriginal width];
            const NSUInteger h = [rawOriginal height];
            
            Renderer::Txt raw = renderer().createTexture(MTLPixelFormatR32Float, w, h);
            Renderer::Txt filteredHTxt = renderer().createTexture(MTLPixelFormatR32Float, w, h);
            Renderer::Txt filteredVTxt = renderer().createTexture(MTLPixelFormatR32Float, w, h);
            Renderer::Txt diffHTxt = renderer().createTexture(MTLPixelFormatR32Float, w, h);
            Renderer::Txt diffVTxt = renderer().createTexture(MTLPixelFormatR32Float, w, h);
            Renderer::Txt diffGRTxt = renderer().createTexture(MTLPixelFormatR32Float, w, h);
            Renderer::Txt diffGBTxt = renderer().createTexture(MTLPixelFormatR32Float, w, h);
            
            // Copy `rawOriginal` so we can modify it
            renderer().copy(rawOriginal, raw);
            
            // Gamma before (improves quality of edges)
            if (opts.applyGamma) {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::GammaForward", raw,
                    // Texture args
                    raw
                );
            }
            
            // Horizontal interpolation
            {
                const bool h = true;
                renderer().render("CFAViewer::Shader::DebayerLMMSE::Interp5", filteredHTxt,
                    // Buffer args
                    h,
                    // Texture args
                    raw
                );
            }
            
            // Vertical interpolation
            {
                const bool h = false;
                renderer().render("CFAViewer::Shader::DebayerLMMSE::Interp5", filteredVTxt,
                    // Buffer args
                    h,
                    // Texture args
                    raw
                );
            }
            
            // Calculate DiffH
            {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::NoiseEst", diffHTxt,
                    // Buffer args
                    opts.cfaDesc,
                    // Texture args
                    raw,
                    filteredHTxt
                );
            }
            
            // Calculate DiffV
            {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::NoiseEst", diffVTxt,
                    // Buffer args
                    opts.cfaDesc,
                    // Texture args
                    raw,
                    filteredVTxt
                );
            }
            
            // Smooth DiffH
            {
                const bool h = true;
                renderer().render("CFAViewer::Shader::DebayerLMMSE::Smooth9", filteredHTxt,
                    // Buffer args
                    h,
                    // Texture args
                    diffHTxt
                );
            }
            
            // Smooth DiffV
            {
                const bool h = false;
                renderer().render("CFAViewer::Shader::DebayerLMMSE::Smooth9", filteredVTxt,
                    // Buffer args
                    h,
                    // Texture args
                    diffVTxt
                );
            }
            
            // Calculate rgb.g
            {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcG", rgb,
                    // Buffer args
                    opts.cfaDesc,
                    // Texture args
                    raw,
                    filteredHTxt,
                    diffHTxt,
                    filteredVTxt,
                    diffVTxt
                );
            }
            
            // Calculate diffGRTxt.r
            {
                const bool modeGR = true;
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcDiffGRGB", diffGRTxt,
                    // Buffer args
                    modeGR,
                    // Texture args
                    raw,
                    rgb
                );
            }
            
            // Calculate diffGBTxt.b
            {
                const bool modeGR = false;
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcDiffGRGB", diffGBTxt,
                    // Buffer args
                    modeGR,
                    // Texture args
                    raw,
                    rgb
                );
            }
            
            // Calculate diffGRTxt.b
            {
                const bool modeGR = true;
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcDiagAvgDiffGRGB", diffGRTxt,
                    // Buffer args
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
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcDiagAvgDiffGRGB", diffGBTxt,
                    // Buffer args
                    modeGR,
                    // Texture args
                    raw,
                    rgb,
                    diffGBTxt
                );
            }
            
            // Calculate diffGRTxt.g
            {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcAxialAvgDiffGRGB", diffGRTxt,
                    // Texture args
                    raw,
                    rgb,
                    diffGRTxt
                );
            }
            
            // Calculate diffGBTxt.g
            {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcAxialAvgDiffGRGB", diffGBTxt,
                    // Texture args
                    raw,
                    rgb,
                    diffGBTxt
                );
            }
            
            // Calculate rgb.rb
            {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::CalcRB", rgb,
                    // Texture args
                    rgb,
                    diffGRTxt,
                    diffGBTxt
                );
            }
            
            // Gamma after (improves quality of edges)
            if (opts.applyGamma) {
                renderer().render("CFAViewer::Shader::DebayerLMMSE::GammaReverse", rgb,
                    // Texture args
                    rgb
                );
            }
        }
    };
};
