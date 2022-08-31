#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "ImagePipelineTypes.h"
#import "../MetalUtil.h"

namespace MDCStudio::ImagePipeline {
    class LocalContrast {
    public:
        static void Run(MDCTools::Renderer& renderer, float amount, float radius, id<MTLTexture> rgb) {
            using namespace MDCTools;
            
            const size_t w = [rgb width];
            const size_t h = [rgb height];
            // Extract L
            Renderer::Txt lTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
            renderer.render(lTxt,
                renderer.FragmentShader(ImagePipelineShaderNamespace "LocalContrast::ExtractL",
                    rgb
                )
            );
            
            // Blur L channel
            Renderer::Txt blurredLTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h,
                MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
            MPSImageGaussianBlur* blur = [[MPSImageGaussianBlur alloc] initWithDevice:renderer.dev
                sigma:radius];
            [blur setEdgeMode:MPSImageEdgeModeClamp];
            [blur encodeToCommandBuffer:renderer.cmdBuf()
                sourceTexture:lTxt destinationTexture:blurredLTxt];
            
            // Local contrast
            renderer.render(rgb,
                renderer.FragmentShader(ImagePipelineShaderNamespace "LocalContrast::LocalContrast",
                    amount,
                    rgb,
                    blurredLTxt
                )
            );
        }
    };
};
