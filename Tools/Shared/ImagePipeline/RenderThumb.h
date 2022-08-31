#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "ImagePipelineTypes.h"
#import "../Renderer.h"

namespace MDCTools::ImagePipeline {

class RenderThumb {
public:
    struct Options {
        size_t thumbWidth = 0;
        size_t thumbHeight = 0;
        size_t dataOff = 0;
    };
    
    static void RGB3FromTexture(MDCTools::Renderer& renderer, const Options& opts, id<MTLTexture> src, id<MTLBuffer> dst) {
        using namespace MDCTools;
        
        assert(opts.dataOff <= [dst length]);
        
        // Ensure that the destination is large enough
        const size_t capNeeded = opts.thumbWidth*opts.thumbHeight*3;
        assert([dst length]-opts.dataOff >= capNeeded);
        
        Renderer::Txt thumbTxtRef;
        id<MTLTexture> thumbTxt = src;
        const bool resize = (opts.thumbWidth!=[src width] || opts.thumbHeight!=[src height]);
        if (resize) {
            thumbTxtRef = renderer.textureCreate(MTLPixelFormatRGBA8Unorm, opts.thumbWidth, opts.thumbHeight,
                MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
            thumbTxt = thumbTxtRef;
            
            MPSImageLanczosScale* resample = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
            [resample encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:src destinationTexture:thumbTxt];
        }
        
        renderer.render(opts.thumbWidth, opts.thumbHeight,
            renderer.FragmentShader(ImagePipelineShaderNamespace "RenderThumb::RGB3FromTexture",
                // Buffer args
                (uint32_t)opts.dataOff,
                (uint32_t)opts.thumbWidth,
                dst,
                // Texture args
                thumbTxt
            )
        );
    }
    
    static void TextureFromRGB3(MDCTools::Renderer& renderer, const Options& opts, id<MTLBuffer> src, id<MTLTexture> dst) {
        using namespace MDCTools;
        
        assert(opts.dataOff <= [src length]);
        
        // Ensure that the destination is large enough
        const size_t capNeeded = opts.thumbWidth*opts.thumbHeight*3;
        assert([src length]-opts.dataOff >= capNeeded);
        
        Renderer::Txt thumbTxtRef;
        id<MTLTexture> thumbTxt = dst;
        const bool resize = (opts.thumbWidth!=[dst width] || opts.thumbHeight!=[dst height]);
        if (resize) {
            thumbTxtRef = renderer.textureCreate(MTLPixelFormatRGBA8Unorm, opts.thumbWidth, opts.thumbHeight,
                MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
            thumbTxt = thumbTxtRef;
        }
        
        renderer.render(thumbTxt,
            renderer.FragmentShader(ImagePipelineShaderNamespace "RenderThumb::TextureFromRGB3",
                // Buffer args
                (uint32_t)opts.dataOff,
                (uint32_t)opts.thumbWidth,
                src
            )
        );
        
        if (resize) {
            // Resample
            MPSImageLanczosScale* resample = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
            [resample encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:thumbTxt destinationTexture:dst];
        }
    }
//
//private:
//    constexpr MTLResourceOptions _BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
};

} // namespace MDCTools::ImagePipeline
