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
static const simd::float4 _BackgroundColor = {
    (float)WindowBackgroundColor.lsrgb[0],
    (float)WindowBackgroundColor.lsrgb[1],
    (float)WindowBackgroundColor.lsrgb[2],
    1
};

@interface ImageLayer : CAMetalLayer
@end

@implementation ImageLayer {
@public
    ImageThumb imageThumb;
    ImagePtr image;
    
    // visibleBounds: for handling NSWindow 'full size' content, where the window
    // content is positioned below the transparent window titlebar for aesthetics
    CGRect visibleBounds;

@private
    ImageCachePtr _imageCache;
    CGFloat _contentsScale;
    
    id<MTLDevice> _device;
    
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
    
    _renderer = MDCTools::Renderer(_device, [_device newDefaultLibrary], [_device newCommandQueue]);
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
    
    // See visibleBounds comment above
    const size_t dstWidth = std::min((size_t)lround(visibleBounds.size.width*_contentsScale), (size_t)[drawableTxt width]);
    const size_t dstHeight = std::min((size_t)lround(visibleBounds.size.height*_contentsScale), (size_t)[drawableTxt height]);
    
    const float srcAspect = (float)ImageThumb::ThumbWidth/ImageThumb::ThumbHeight;
    const float dstAspect = (float)dstWidth/dstHeight;
    
    size_t imageWidth = dstWidth;
    size_t imageHeight = dstHeight;
    if (srcAspect > dstAspect) {
        // Destination width determines size
        imageHeight = lround(imageWidth/srcAspect);
    } else {
        // Destination height determines size
        imageWidth = lround(imageHeight*srcAspect);
    }
    
    auto imageTxt = _renderer.textureCreate(MTLPixelFormatBGRA8Unorm, imageWidth, imageHeight,
        MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    
    constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
    id<MTLBuffer> thumbBuf = [_device newBufferWithBytes:imageThumb.thumb length:sizeof(imageThumb.thumb) options:BufOpts];
    const RenderThumb::Options thumbOpts = {
        .thumbWidth = ImageThumb::ThumbWidth,
        .thumbHeight = ImageThumb::ThumbHeight,
        .dataOff = 0,
    };
    RenderThumb::TextureFromRGB3(_renderer, thumbOpts, thumbBuf, imageTxt);
    
    // topInset is for handling NSWindow 'full size' content; see visibleBounds comment above
    const size_t topInset = [drawableTxt height]-dstHeight;
    
    const simd::int2 off = {
        (simd::int1)((dstWidth-imageWidth)/2),
        (simd::int1)topInset+(simd::int1)((dstHeight-imageHeight)/2)
    };
    
    _renderer.render("MDCStudio::ImageViewShader::FragmentShader", drawableTxt,
        // Buffer args
        off,
        _BackgroundColor,
        // Texture args
        imageTxt
    );
    
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
    
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
        NSLog(@"ImageView: %f", [self frame].size.height);
    }];
    
    return self;
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    
    const CGRect bounds = [self bounds];
    const CGRect contentLayoutRect = [self convertRect:[[self window] contentLayoutRect] fromView:nil];
//    NSLog(@"contentLayoutRect: %@", NSStringFromRect([[self window] contentLayoutRect]));
//    NSLog(@"contentView frame: %@", NSStringFromRect([[[self window] contentView] frame]));
    _layer->visibleBounds = CGRectIntersection(bounds, contentLayoutRect);
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:[[self window] backingScaleFactor]];
}

- (const ImageThumb&)imageThumb {
    return _layer->imageThumb;
}

@end
