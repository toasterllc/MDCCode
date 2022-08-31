#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "../MetalUtil.h"
#import "ImagePipelineTypes.h"

namespace MDCTools::ImagePipeline {

class DebayerLMMSE {
public:
    static void Run(
        MDCTools::Renderer& renderer,
        const MDCTools::CFADesc& cfaDesc,
        bool applyGamma,
        id<MTLTexture> srcRaw,
        id<MTLTexture> dstRGB
    ) {
        
        using namespace MDCTools;
        
        const size_t w = [srcRaw width];
        const size_t h = [srcRaw height];
        
        Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        
        // Copy `srcRaw` so we can modify it
        renderer.copy(srcRaw, raw);
        
        // Gamma before (improves quality of edges)
        if (applyGamma) {
            renderer.render(raw,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::GammaForward",
                    // Texture args
                    raw
                )
            );
        }
        
        // Horizontal interpolation
        Renderer::Txt filteredHTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool h = true;
            renderer.render(filteredHTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::Interp5",
                    // Buffer args
                    h,
                    // Texture args
                    raw
                )
            );
        }
        
        // Vertical interpolation
        Renderer::Txt filteredVTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool h = false;
            renderer.render(filteredVTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::Interp5",
                    // Buffer args
                    h,
                    // Texture args
                    raw
                )
            );
        }
        
        // Calculate DiffH
        Renderer::Txt diffHTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            renderer.render(diffHTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::NoiseEst",
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    filteredHTxt
                )
            );
        }
        
        // Calculate DiffV
        Renderer::Txt diffVTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            renderer.render(diffVTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::NoiseEst",
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    filteredVTxt
                )
            );
        }
        
        // Smooth DiffH
        {
            const bool h = true;
            renderer.render(filteredHTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::Smooth9",
                    // Buffer args
                    h,
                    // Texture args
                    diffHTxt
                )
            );
        }
        
        // Smooth DiffV
        {
            const bool h = false;
            renderer.render(filteredVTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::Smooth9",
                    // Buffer args
                    h,
                    // Texture args
                    diffVTxt
                )
            );
        }
        
        // Calculate dstRGB.g
        {
            renderer.render(dstRGB,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcG",
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    filteredHTxt,
                    diffHTxt,
                    filteredVTxt,
                    diffVTxt
                )
            );
        }
        
        // Calculate diffGRTxt.r
        Renderer::Txt diffGRTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool modeGR = true;
            renderer.render(diffGRTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiffGRGB",
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    dstRGB
                )
            );
        }
        
        // Calculate diffGBTxt.b
        Renderer::Txt diffGBTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
        {
            const bool modeGR = false;
            renderer.render(diffGBTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiffGRGB",
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    dstRGB
                )
            );
        }
        
        // Calculate diffGRTxt.b
        {
            const bool modeGR = true;
            renderer.render(diffGRTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiagAvgDiffGRGB",
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    dstRGB,
                    diffGRTxt
                )
            );
        }
        
        // Calculate diffGBTxt.r
        {
            const bool modeGR = false;
            renderer.render(diffGBTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcDiagAvgDiffGRGB",
                    // Buffer args
                    cfaDesc,
                    modeGR,
                    // Texture args
                    raw,
                    dstRGB,
                    diffGBTxt
                )
            );
        }
        
        // Calculate diffGRTxt.g
        {
            renderer.render(diffGRTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcAxialAvgDiffGRGB",
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    dstRGB,
                    diffGRTxt
                )
            );
        }
        
        // Calculate diffGBTxt.g
        {
            renderer.render(diffGBTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcAxialAvgDiffGRGB",
                    // Buffer args
                    cfaDesc,
                    // Texture args
                    raw,
                    dstRGB,
                    diffGBTxt
                )
            );
        }
        
        // Calculate dstRGB.rb
        {
            renderer.render(dstRGB,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::CalcRB",
                    // Texture args
                    dstRGB,
                    diffGRTxt,
                    diffGBTxt
                )
            );
        }
        
        // Gamma after (improves quality of edges)
        if (applyGamma) {
            renderer.render(dstRGB,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerLMMSE::GammaReverse",
                    // Texture args
                    dstRGB
                )
            );
        }
    }
};

}; // namespace MDCTools::ImagePipeline
