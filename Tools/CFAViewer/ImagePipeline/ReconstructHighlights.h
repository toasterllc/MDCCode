#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipelineTypes.h"
#import "MetalUtil.h"

namespace CFAViewer::ImagePipeline {
    class ReconstructHighlights {
    public:
        static void Run(Renderer& renderer, const CFADesc& cfaDesc, const Mat<double,3,1>& illum, id<MTLTexture> raw) {
            const size_t w = [raw width];
            const size_t h = [raw height];
            Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float, w/2, h/2);
            renderer.render("CFAViewer::Shader::ImagePipeline::DebayerDownsample", rgb,
                // Buffer args
                cfaDesc,
                // Texture args
                raw,
                rgb
            );
            
            // `Scale` balances the raw colors from the sensor for the purpose
            // of highlight reconstruction (empirically determined)
            const simd::float3 Scale = {1.179, 0.649, 1.180};
            // `Thresh` is the threshold at which pixels are considered for
            // highlight reconstruction (empirically determined)
            const float Thresh = 0.774;
            const double illumMin = std::min(std::min(illum[0], illum[1]), illum[2]);
            const Mat<double,3,1> illumMin1 = illum/illumMin;
            const simd::float3 simdIllumMin1 = {(float)illumMin1[0], (float)illumMin1[1], (float)illumMin1[2]};
            Renderer::Txt highlightMap = renderer.textureCreate(MTLPixelFormatRG32Float, w, h);
            renderer.render("CFAViewer::Shader::ReconstructHighlights::CreateHighlightMap", highlightMap,
                // Buffer args
                Scale,
                Thresh,
                simdIllumMin1,
                // Texture args
                rgb
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
                cfaDesc,
                simdIllumMin1,
                // Texture args
                raw,
                rgb,
                highlightMap
            );
        }
    };
};
