#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "ImagePipelineTypes.h"
#import "MetalUtil.h"

namespace CFAViewer::ImagePipeline {
    class LocalContrast {
    public:
        static void Run(Renderer& renderer, float amount, float radius, id<MTLTexture> rgb) {
            const NSUInteger w = [rgb width];
            const NSUInteger h = [rgb height];
            // Extract L
            Renderer::Txt lTxt = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
            renderer.render("CFAViewer::Shader::LocalContrast::ExtractL", lTxt,
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
            renderer.render("CFAViewer::Shader::LocalContrast::LocalContrast", rgb,
                amount,
                rgb,
                blurredLTxt
            );
        }
    };
};
