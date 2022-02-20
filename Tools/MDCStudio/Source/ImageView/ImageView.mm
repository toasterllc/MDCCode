#import "ImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "Util.h"
#import "ImagePipeline/RenderThumb.h"
using namespace MDCStudio;

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

@interface ImageLayer : CAMetalLayer
@end

@implementation ImageLayer {
@public
    ImageThumb imageThumb;
    ImagePtr image;

@private
    ImageCachePtr _imageCache;
    CGFloat _contentsScale;
    
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    
    MDCTools::Renderer _renderer;
}

- (instancetype)initWithImageThumb:(const ImageThumb&)imageThumbArg imageCache:(ImageCachePtr)imageCache {
    if (!(self = [super init])) return nil;
    
    imageThumb = imageThumbArg;
    _imageCache = imageCache;
    _contentsScale = 1;
    
    [self setOpaque:true];
    [self setActions:LayerNullActions];
    [self setNeedsDisplayOnBoundsChange:true];
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    
    _commandQueue = [_device newCommandQueue];
    
    id<MTLLibrary> library = [_device newDefaultLibrary];
    assert(library);
    
    id<MTLFunction> vertexShader = [library newFunctionWithName:@"MDCStudio::ImageViewShader::VertexShader"];
    assert(vertexShader);
    
    id<MTLFunction> fragmentShader = [library newFunctionWithName:@"MDCStudio::ImageViewShader::FragmentShader"];
    assert(fragmentShader);
    
    _renderer = MDCTools::Renderer(_device, library, _commandQueue);
    return self;
}

- (void)display {
    using namespace MDCTools;
    using namespace MDCStudio::ImagePipeline;
    
    auto startTime = std::chrono::steady_clock::now();
    
    // Bail if we have zero width/height; the Metal drawable APIs will fail below
    // if we don't short-circuit here.
    const CGRect frame = [self frame];
    if (CGRectIsEmpty(frame)) return;
    
    // Update our drawable size
    [self setDrawableSize:{frame.size.width*_contentsScale, frame.size.height*_contentsScale}];
    
    // Get our drawable and its texture
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    auto thumbTxt = _renderer.textureCreate(MTLPixelFormatBGRA8Unorm, [drawableTxt width], [drawableTxt height],
        MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    
    constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
    id<MTLBuffer> thumbBuf = [_device newBufferWithBytes:imageThumb.thumb length:sizeof(imageThumb.thumb) options:BufOpts];
    const RenderThumb::Options thumbOpts = {
        .thumbWidth = ImageThumb::ThumbWidth,
        .thumbHeight = ImageThumb::ThumbHeight,
        .dataOff = 0,
    };
    RenderThumb::TextureFromRGB3(_renderer, thumbOpts, thumbBuf, thumbTxt);
    _renderer.copy(thumbTxt, drawableTxt);
    _renderer.present(drawable);
    _renderer.commitAndWait();
    
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
    printf("Took %ju ms\n", (uintmax_t)durationMs);
}

- (void)setContentsScale:(CGFloat)scale {
    _contentsScale = scale;
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

@end

@implementation ImageView {
    ImageLayer* _layer;
}

- (instancetype)initWithImageThumb:(const MDCStudio::ImageThumb&)imageThumb
    imageCache:(MDCStudio::ImageCachePtr)imageCache {
    
    if (!(self = [super initWithFrame:{}])) return nil;
    _layer = [[ImageLayer alloc] initWithImageThumb:imageThumb imageCache:imageCache];
    [self setLayer:_layer];
    [self setWantsLayer:true];
    return self;
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:[[self window] backingScaleFactor]];
}

- (const ImageThumb&)imageThumb {
    return _layer->imageThumb;
}

@end
