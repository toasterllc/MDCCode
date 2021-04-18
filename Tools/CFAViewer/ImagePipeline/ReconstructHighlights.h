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
            renderer.render("CFAViewer::Shader::ReconstructHighlights::DebayerDownsample", rgb,
                // Buffer args
                cfaDesc,
                // Texture args
                raw
            );
            
//            Renderer::Txt thresh = renderer.textureCreate(MTLPixelFormatR32Float, w/2, h/2);
//            renderer.render("CFAViewer::Shader::ReconstructHighlights::Normalize", thresh,
//                // Buffer args
//                scale,
//                // Texture args
//                rgb
//            );
            
            const simd::float3 scale = {1.179, 0.649, 1.180}; // Empirically determined
            const float cutoff = 0.7741562512; // Empirically determined
            const double illumMin = std::min(std::min(illum[0], illum[1]), illum[2]);
            const Mat<double,3,1> illumMin1 = illum/illumMin;
            const simd::float3 simdIllumMin1 = {(float)illumMin1[0], (float)illumMin1[1], (float)illumMin1[2]};
            Renderer::Txt highlightMap = renderer.textureCreate(MTLPixelFormatRG32Float, w, h);
            renderer.render("CFAViewer::Shader::ReconstructHighlights::CreateHighlightMap", highlightMap,
                // Buffer args
                scale,
                cutoff,
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
