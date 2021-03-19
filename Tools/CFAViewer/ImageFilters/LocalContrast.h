#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImageFilter.h"
#import "MetalUtil.h"

namespace CFAViewer::ImageFilter {
    class LocalContrast {
    public:
        static void Run(Renderer& renderer, float amount, float radius, id<MTLTexture> rgb) {
            const NSUInteger w = [rgb width];
            const NSUInteger h = [rgb height];
            // Extract L
            Renderer::Txt lTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h);
            renderer.render("CFAViewer::Shader::LocalContrast::ExtractL", lTxt,
                rgb
            );
            
            // Blur L channel
            Renderer::Txt blurredLTxt = renderer.createTexture(MTLPixelFormatR32Float, w, h,
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
