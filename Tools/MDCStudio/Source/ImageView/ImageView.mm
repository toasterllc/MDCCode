#import "ImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "Util.h"
#import "ImagePipeline/RenderThumb.h"
#import "ImagePipeline/ImagePipeline.h"
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
    
    // visibleBounds: for handling NSWindow 'full size' content, where the window
    // content is positioned below the transparent window titlebar for aesthetics
    CGRect visibleBounds;

@private
    ImagePtr _image;
    id<MTLTexture> _imageTexture;
    ImageSourcePtr _imageSource;
    CGFloat _contentsScale;
    
    MDCTools::Renderer _renderer;
}

- (instancetype)initWithImageThumb:(const ImageThumb&)imageThumbArg imageSource:(ImageSourcePtr)imageSource {
    if (!(self = [super init])) return nil;
    
    imageThumb = imageThumbArg;
    _imageSource = imageSource;
    _contentsScale = 1;
    
    [self setOpaque:true];
    [self setActions:LayerNullActions];
    [self setNeedsDisplayOnBoundsChange:true];
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device);
    [self setDevice:device];
    [self setPixelFormat:_PixelFormat];
    
    _renderer = MDCTools::Renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
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
    
    // Destination width determines size
    if (srcAspect > dstAspect) imageHeight = lround(imageWidth/srcAspect);
    // Destination height determines size
    else imageWidth = lround(imageHeight*srcAspect);
    
    auto imageTxt = _renderer.textureCreate(MTLPixelFormatBGRA8Unorm, imageWidth, imageHeight,
        MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    
    // Fetch the image from the cache, if we don't have _image yet
    if (!_image) {
        __weak auto weakSelf = self;
        _image = _imageSource->imageCache()->imageForImageRef(imageThumb.ref, [=] (ImagePtr image) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf _handleImageLoaded:image]; });
        });
    }
    
    // Render _imageTexture if it doesn't exist yet and we have the image
    if (!_imageTexture && _image) {
        Pipeline::RawImage rawImage = {
            .cfaDesc    = _image->cfaDesc,
            .width      = _image->width,
            .height     = _image->height,
            .pixels     = (ImagePixel*)(_image->data.get() + _image->off),
        };
        
        const Pipeline::Options pipelineOpts = {
            .reconstructHighlights  = { .en = true, },
            .debayerLMMSE           = { .applyGamma = true, },
        };
        
        Pipeline::Result renderResult = Pipeline::Run(_renderer, rawImage, pipelineOpts);
        _imageTexture = renderResult.txt;
    }
    
    if (_imageTexture) {
        // Resample
        MPSImageLanczosScale* resample = [[MPSImageLanczosScale alloc] initWithDevice:_renderer.dev];
        [resample encodeToCommandBuffer:_renderer.cmdBuf() sourceTexture:_imageTexture destinationTexture:imageTxt];
    
    // Otherwise, render the thumbnail
    } else {
        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
        id<MTLBuffer> thumbBuf = [_renderer.dev newBufferWithBytes:imageThumb.thumb length:sizeof(imageThumb.thumb) options:BufOpts];
        const RenderThumb::Options thumbOpts = {
            .thumbWidth = ImageThumb::ThumbWidth,
            .thumbHeight = ImageThumb::ThumbHeight,
            .dataOff = 0,
        };
        RenderThumb::TextureFromRGB3(_renderer, thumbOpts, thumbBuf, imageTxt);
    }
    
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

- (void)_handleImageLoaded:(ImagePtr)image {
    _image = image;
    [self setNeedsDisplay];
}

- (void)setContentsScale:(CGFloat)scale {
    _contentsScale = scale;
    [super setContentsScale:scale];
    [self setNeedsDisplay];
}

@end

@implementation ImageView {
    ImageLayer* _layer;
    __weak id<ImageViewDelegate> _delegate;
}

- (instancetype)initWithImageThumb:(const MDCStudio::ImageThumb&)imageThumb
    imageSource:(MDCStudio::ImageSourcePtr)imageSource {
    
    if (!(self = [super initWithFrame:{}])) return nil;
    _layer = [[ImageLayer alloc] initWithImageThumb:imageThumb imageSource:imageSource];
    [self setLayer:_layer];
    [self setWantsLayer:true];
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        NSLog(@"ImageView: %f", [self frame].size.height);
//    }];
    
    return self;
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    
    const CGRect bounds = [self bounds];
    const CGRect contentLayoutRect = [self convertRect:[[self window] contentLayoutRect] fromView:nil];
    _layer->visibleBounds = CGRectIntersection(bounds, contentLayoutRect);
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_layer setContentsScale:[[self window] backingScaleFactor]];
}

- (const ImageThumb&)imageThumb {
    return _layer->imageThumb;
}

- (void)setDelegate:(id<ImageViewDelegate>)delegate {
    _delegate = delegate;
}

// MARK: - Event Handling

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
}

- (void)moveLeft:(id)sender {
    [_delegate imageViewPreviousImage:self];
}

- (void)moveRight:(id)sender {
    [_delegate imageViewNextImage:self];
}

@end
