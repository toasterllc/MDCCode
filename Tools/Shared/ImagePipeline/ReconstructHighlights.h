#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "ImagePipelineTypes.h"
#import "../MetalUtil.h"
#import "Debug.h"

namespace MDCTools::ImagePipeline {

class ReconstructHighlights {
public:
    static void Run(
        MDCTools::Renderer& renderer,
        const MDCTools::CFADesc& cfaDesc,
        const Mat<double,3,1>& illum,
        id<MTLTexture> raw
    ) {
        
        using namespace MDCTools;
        
        const size_t w = [raw width];
        const size_t h = [raw height];
        Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float, w/2, h/2);
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::DebayerDownsample",
                // Buffer args
                cfaDesc,
                (uint32_t)[rgb width],
                (uint32_t)[rgb height],
                // Texture args
                raw
            )
        );
        
        Renderer::Txt thresholdMap = renderer.textureCreate(MTLPixelFormatR32Float, w, h,
            MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite
        );
        renderer.render(thresholdMap,
            renderer.FragmentShader(ImagePipelineShaderNamespace "ReconstructHighlights::CreateThresholdMap",
                // Texture args
                rgb
            )
        );
        
        {
            // Blur thresholdMap
            Renderer::Txt thresholdMapBlurred = renderer.textureCreate(thresholdMap);
            float radius = 20;
            MPSImageGaussianBlur* blur = [[MPSImageGaussianBlur alloc] initWithDevice:renderer.dev sigma:radius];
            [blur setEdgeMode:MPSImageEdgeModeClamp];
            [blur encodeToCommandBuffer:renderer.cmdBuf()
                sourceTexture:thresholdMap destinationTexture:thresholdMapBlurred];
            thresholdMap = std::move(thresholdMapBlurred);
        }
        
//        renderer.debugTextureShow(thresholdMap);
        
        // `Scale` balances the raw colors from the sensor for the purpose
        // of highlight reconstruction (empirically determined)
        const simd::float3 Scale = { 1.179, 0.649, 1.180 };
        // `Thresh` is the threshold at which pixels are considered for
        // highlight reconstruction (empirically determined)
        const float Thresh = Debug::Thresh;
        const double illumMin = std::min(std::min(illum[0], illum[1]), illum[2]);
        const Mat<double,3,1> illumMin1 = illum/illumMin;
        const simd::float3 simdIllumMin1 = {(float)illumMin1[0], (float)illumMin1[1], (float)illumMin1[2]};
        Renderer::Txt highlightMap = renderer.textureCreate(MTLPixelFormatRG32Float, w, h);
        renderer.render(highlightMap,
            renderer.FragmentShader(ImagePipelineShaderNamespace "ReconstructHighlights::CreateHighlightMap",
                // Buffer args
                Scale,
                simdIllumMin1,
                // Texture args
                rgb,
                thresholdMap
            )
        );
        
//        renderer.debugShowTexture(raw);
        
        for (int i=0; i<1; i++) {
            Renderer::Txt tmp = renderer.textureCreate(highlightMap);
            renderer.render(tmp,
                renderer.FragmentShader(ImagePipelineShaderNamespace "ReconstructHighlights::Blur",
                    // Texture args
                    highlightMap
                )
            );
            highlightMap = std::move(tmp);
        }
        
        renderer.render(raw,
            renderer.FragmentShader(ImagePipelineShaderNamespace "ReconstructHighlights::ReconstructHighlights",
                // Buffer args
                cfaDesc,
                simdIllumMin1,
                // Texture args
                raw,
                rgb,
                highlightMap
            )
        );
    }
};

}; // MDCTools::ImagePipeline
