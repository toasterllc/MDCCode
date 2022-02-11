#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "Tools/Shared/MetalUtil.h"
#import "ImagePipelineTypes.h"

namespace MDCStudio::ImagePipeline {

class DebayerLMMSE {
public:
    static void Run(MDCTools::Renderer& renderer, const CFADesc& cfaDesc, bool applyGamma, id<MTLTexture> srcRaw, id<MTLTexture> dstRGB) {
        
        using namespace MDCTools;
        
        const size_t w = [srcRaw width];
        const size_t h = [srcRaw height];
        
        Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        
        // Copy `srcRaw` so we can modify it
        renderer.copy(srcRaw, raw);
        
        // Gamma before (improves quality of edges)
        if (applyGamma) {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::GammaForward", raw,
                // Texture args
                raw
            );
        }
        
        // Horizontal interpolation
        Renderer::Txt filteredHTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool h = true;
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::Interp5", filteredHTxt,
                // Buffer args
                h,
                // Texture args
                raw
            );
        }
        
        // Vertical interpolation
        Renderer::Txt filteredVTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool h = false;
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::Interp5", filteredVTxt,
                // Buffer args
                h,
                // Texture args
                raw
            );
        }
        
        // Calculate DiffH
        Renderer::Txt diffHTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::NoiseEst", diffHTxt,
                // Buffer args
                cfaDesc,
                // Texture args
                raw,
                filteredHTxt
            );
        }
        
        // Calculate DiffV
        Renderer::Txt diffVTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::NoiseEst", diffVTxt,
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
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::Smooth9", filteredHTxt,
                // Buffer args
                h,
                // Texture args
                diffHTxt
            );
        }
        
        // Smooth DiffV
        {
            const bool h = false;
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::Smooth9", filteredVTxt,
                // Buffer args
                h,
                // Texture args
                diffVTxt
            );
        }
        
        // Calculate dstRGB.g
        {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcG", dstRGB,
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
        Renderer::Txt diffGRTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool modeGR = true;
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiffGRGB", diffGRTxt,
                // Buffer args
                cfaDesc,
                modeGR,
                // Texture args
                raw,
                dstRGB
            );
        }
        
        // Calculate diffGBTxt.b
        Renderer::Txt diffGBTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool modeGR = false;
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiffGRGB", diffGBTxt,
                // Buffer args
                cfaDesc,
                modeGR,
                // Texture args
                raw,
                dstRGB
            );
        }
        
        // Calculate diffGRTxt.b
        {
            const bool modeGR = true;
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiagAvgDiffGRGB", diffGRTxt,
                // Buffer args
                cfaDesc,
                modeGR,
                // Texture args
                raw,
                dstRGB,
                diffGRTxt
            );
        }
        
        // Calculate diffGBTxt.r
        {
            const bool modeGR = false;
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiagAvgDiffGRGB", diffGBTxt,
                // Buffer args
                cfaDesc,
                modeGR,
                // Texture args
                raw,
                dstRGB,
                diffGBTxt
            );
        }
        
        // Calculate diffGRTxt.g
        {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcAxialAvgDiffGRGB", diffGRTxt,
                // Buffer args
                cfaDesc,
                // Texture args
                raw,
                dstRGB,
                diffGRTxt
            );
        }
        
        // Calculate diffGBTxt.g
        {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcAxialAvgDiffGRGB", diffGBTxt,
                // Buffer args
                cfaDesc,
                // Texture args
                raw,
                dstRGB,
                diffGBTxt
            );
        }
        
        // Calculate dstRGB.rb
        {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::CalcRB", dstRGB,
                // Texture args
                dstRGB,
                diffGRTxt,
                diffGBTxt
            );
        }
        
        // Gamma after (improves quality of edges)
        if (applyGamma) {
            renderer.render(ImagePipelineShaderNamespace "DebayerLMMSE::GammaReverse", dstRGB,
                // Texture args
                dstRGB
            );
        }
    }
};

}; // namespace MDCStudio::ImagePipeline
