#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

namespace MDCStudio::ImagePipeline {

class RenderThumb {
public:
    struct Options {
        size_t thumbWidth = 0;
        size_t thumbHeight = 0;
        void* dst = nullptr;
        size_t dstOff = 0;
        size_t dstCap = 0;
    };
    
    static void Run(MDCTools::Renderer& renderer, const Options& opts, id<MTLTexture> srcRGB) {
        using namespace MDCTools;
        
        assert(opts.dstOff <= opts.dstCap);
        
        // Ensure that the destination is large enough
        const size_t capNeeded = opts.thumbWidth*opts.thumbHeight*3;
        assert(opts.dstCap-opts.dstOff >= capNeeded);
        
        Renderer::Txt thumbTxt = renderer.textureCreate(MTLPixelFormatRGBA8Unorm, opts.thumbWidth, opts.thumbHeight,
            MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
        MPSImageLanczosScale* downsample = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
        [downsample encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:srcRGB destinationTexture:thumbTxt];
        
        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
        id<MTLBuffer> thumbBuf = [renderer.dev newBufferWithBytesNoCopy:opts.dst length:opts.dstCap options:BufOpts deallocator:nil];
        if (!thumbBuf) throw Toastbox::RuntimeError("failed to create MTLBuffer");
        
        renderer.render(ImagePipelineShaderNamespace "RenderThumb::RenderThumb", opts.thumbWidth, opts.thumbHeight,
            // Buffer args
            (uint32_t)opts.dstOff,
            (uint32_t)opts.thumbWidth,
            thumbBuf,
            // Texture args
            thumbTxt
        );
    }
};

} // namespace MDCStudio::ImagePipeline
