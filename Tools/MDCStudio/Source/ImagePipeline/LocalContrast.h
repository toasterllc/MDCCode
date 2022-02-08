#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "ImagePipelineTypes.h"
#import "MetalUtil.h"

namespace MDCStudio::ImagePipeline {
    class LocalContrast {
    public:
        static void Run(MDCTools::Renderer& renderer, float amount, float radius, id<MTLTexture> rgb) {
            using namespace MDCTools;
            
            const NSUInteger w = [rgb width];
            const NSUInteger h = [rgb height];
            // Extract L
            Renderer::Txt lTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
            renderer.render(ImagePipelineShaderNamespace "LocalContrast::ExtractL", lTxt,
                rgb
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
            renderer.render(ImagePipelineShaderNamespace "LocalContrast::LocalContrast", rgb,
                amount,
                rgb,
                blurredLTxt
            );
        }
    };
};
