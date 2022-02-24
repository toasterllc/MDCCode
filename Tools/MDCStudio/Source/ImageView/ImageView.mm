#import "ImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "Util.h"
#import "ImagePipeline/RenderThumb.h"
#import "ImagePipeline/ImagePipeline.h"
#import "ImageViewTypes.h"
using namespace MDCStudio;
using namespace MDCStudio::ImageViewTypes;

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
static const simd::float4 _BackgroundColor = {
    (float)WindowBackgroundColor.lsrgb[0],
    (float)WindowBackgroundColor.lsrgb[1],
    (float)WindowBackgroundColor.lsrgb[2],
    1
};


static Mat<float,4,4> _Scale(float x, float y, float z) {
    return {
        x,   0.f, 0.f, 0.f,
        0.f, y,   0.f, 0.f,
        0.f, 0.f, z,   0.f,
        0.f, 0.f, 0.f, 1.f,
    };
}

static Mat<float,4,4> _Translate(float x, float y, float z) {
    return {
        1.f, 0.f, 0.f, x,
        0.f, 1.f, 0.f, y,
        0.f, 0.f, 1.f, z,
        0.f, 0.f, 0.f, 1.f,
    };
}

static simd::float4x4 simdForMat(const Mat<float,4,4>& m) {
    return {
        simd::float4{m.at(0,0), m.at(1,0), m.at(2,0), m.at(3,0)},
        simd::float4{m.at(0,1), m.at(1,1), m.at(2,1), m.at(3,1)},
        simd::float4{m.at(0,2), m.at(1,2), m.at(2,2), m.at(3,2)},
        simd::float4{m.at(0,3), m.at(1,3), m.at(2,3), m.at(3,3)},
    };
}


















@interface ImageLayer : CAMetalLayer
@end

@implementation ImageLayer {
@public
    ImageThumb imageThumb;
    
    // visibleBounds: for handling NSWindow 'full size' content, where the window
    // content is positioned below the transparent window titlebar for aesthetics
    CGRect visibleBounds;
    CGPoint scroll;
    CGFloat magnification;
    
@private
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    
    ImagePtr _image;
    id<MTLTexture> _imageTxt;
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
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    
    id<MTLLibrary> library = [_device newDefaultLibraryWithBundle:[NSBundle bundleForClass:[self class]] error:nil];
    assert(library);
    id<MTLFunction> vertexShader = [library newFunctionWithName:@"MDCStudio::ImageViewShader::VertexShader"];
    assert(vertexShader);
    id<MTLFunction> fragmentShader = [library newFunctionWithName:@"MDCStudio::ImageViewShader::FragmentShader"];
    assert(fragmentShader);
    
    _commandQueue = [_device newCommandQueue];
    
    MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    [pipelineDescriptor setVertexFunction:vertexShader];
    [pipelineDescriptor setFragmentFunction:fragmentShader];
    [[pipelineDescriptor colorAttachments][0] setPixelFormat:_PixelFormat];
    
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
    assert(_pipelineState);
    
    
    
    
    
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
    const size_t drawableWidth = lround(frame.size.width*_contentsScale);
    const size_t drawableHeight = lround(frame.size.height*_contentsScale);
    [self setDrawableSize:{(CGFloat)drawableWidth, (CGFloat)drawableHeight}];
    
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
    
    size_t imageWidth = 2304;//dstWidth;
    size_t imageHeight = 1296;//dstHeight;
    
//    // Destination width determines size
//    if (srcAspect > dstAspect) imageHeight = lround(imageWidth/srcAspect);
//    // Destination height determines size
//    else imageWidth = lround(imageHeight*srcAspect);
    
//    float imageAspect = (imageWidth>imageHeight ? ((float)imageWidth/imageHeight) : ((float)imageWidth/imageHeight));
//    if (imageAspect < 1)
    
    auto imageTxt = _renderer.textureCreate(MTLPixelFormatBGRA8Unorm, imageWidth, imageHeight,
        MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    
//    // Fetch the image from the cache, if we don't have _image yet
//    if (!_image) {
//        __weak auto weakSelf = self;
//        _image = _imageSource->imageCache()->imageForImageRef(imageThumb.ref, [=] (ImagePtr image) {
//            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf _handleImageLoaded:image]; });
//        });
//    }
    
    // Render _imageTxt if it doesn't exist yet and we have the image
    if (!_imageTxt && _image) {
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
        _imageTxt = renderResult.txt;
    }
    
    if (_imageTxt) {
        // Resample
        MPSImageLanczosScale* resample = [[MPSImageLanczosScale alloc] initWithDevice:_renderer.dev];
        [resample encodeToCommandBuffer:_renderer.cmdBuf() sourceTexture:_imageTxt destinationTexture:imageTxt];
    
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
    
//    {
//        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
//        [[renderPassDescriptor colorAttachments][0] setTexture:drawable.texture];
//        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
//        [[renderPassDescriptor colorAttachments][0] setClearColor:{WindowBackgroundColor.lsrgb[0], WindowBackgroundColor.lsrgb[1], WindowBackgroundColor.lsrgb[2], 1}];
//        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
//        
//        id<MTLRenderCommandEncoder> renderEncoder = [_renderer.cmdBuf() renderCommandEncoderWithDescriptor:renderPassDescriptor];
//        [renderEncoder setRenderPipelineState:_pipelineState];
//        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
//        [renderEncoder setCullMode:MTLCullModeNone];
//        [renderEncoder endEncoding];
//    }
    
    {
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor new];
        [[renderPassDescriptor colorAttachments][0] setTexture:drawableTxt];
        [[renderPassDescriptor colorAttachments][0] setLoadAction:MTLLoadActionClear];
        [[renderPassDescriptor colorAttachments][0] setClearColor:{WindowBackgroundColor.lsrgb[0], WindowBackgroundColor.lsrgb[1], WindowBackgroundColor.lsrgb[2], 1}];
        [[renderPassDescriptor colorAttachments][0] setStoreAction:MTLStoreActionStore];
        
        id<MTLRenderCommandEncoder> renderEncoder = [_renderer.cmdBuf() renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeNone];
        
//        const matrix_float4x4 scale = (srcAspect>dstAspect ? _Scale(1, (float)imageHeight/dstHeight, 1) : _Scale((float)imageWidth/dstWidth, 1, 1));
        
//        // rasterFromUnityMatrix: converts unity coordinates [-1,1] -> rasterized coordinates [0,pixel width/height]
//        const matrix_float4x4 rasterFromUnityMatrix = matrix_multiply(matrix_multiply(
//            _Scale(.5*frame.size.width*_contentsScale, .5*frame.size.height*_contentsScale, 1), // Divide by 2, multiply by view width/height
//            _Translate(1, 1, 0)),                                                               // Add 1
//            _Scale(1, -1, 1)                                                                    // Flip Y
//        );
//        
//        // unityFromRasterMatrix: converts rasterized coordinates -> unity coordinates
//        const matrix_float4x4 unityFromRasterMatrix = matrix_invert(rasterFromUnityMatrix);
//        
//        const matrix_float4x4 matrix = matrix_multiply(matrix_multiply(
//            unityFromRasterMatrix,
//            _Translate(scroll.x, scroll.y, 0)),
//            scale
//        );
        
//        const matrix_float4x4 scale = _Scale((float)imageWidth/drawableWidth, (float)imageHeight/drawableHeight, 1);
//        const matrix_float4x4 matrix = matrix_multiply(
//            _Translate((scroll.x*_contentsScale) / drawableWidth, (scroll.y*_contentsScale) / drawableHeight, 0),
//            scale
//        );
        
//        const matrix_float4x4 scale = _Scale((float)imageWidth/drawableWidth, (float)imageHeight/drawableHeight, 1);
        
        // rasterFromUnityMatrix: converts unity coordinates [-1,1] -> rasterized coordinates [0,pixel width/height]
        const Mat<float,4,4> rasterFromUnityMatrix =
            _Scale(.5*frame.size.width*_contentsScale, .5*frame.size.height*_contentsScale, 1) *    // Divide by 2, multiply by view width/height
            _Translate(1, 1, 0) *                                                                   // Add 1
            _Scale(1, -1, 1);                                                                       // Flip Y
        
        
        // unityFromRasterMatrix: converts rasterized coordinates -> unity coordinates
        const Mat<float,4,4> unityFromRasterMatrix = rasterFromUnityMatrix.inv();
        
        Mat<float,4,4> offset;
        
        const float magImageWidth = magnification*imageWidth;
        const float magImageHeight = magnification*imageHeight;
        const float offX = (drawableWidth>magImageWidth ? (float)(drawableWidth-magImageWidth)/2 : 0);
        const float offY = (drawableHeight>magImageHeight ? (float)(drawableHeight-magImageHeight)/2 : 0);
        const Mat<float,4,4> mat =
            unityFromRasterMatrix *
            _Translate(offX, offY, 0) *
            _Scale(magnification, magnification, 1) *
            _Translate(-scroll.x*_contentsScale, -scroll.y*_contentsScale, 0);
//        
////        matrix_multiply(unityFromRasterMatrix, );
//        
//        const matrix_float4x4 matrix = matrix_identity_float4x4;
//        Mat<float,4,4> scale = _Scale((float)imageWidth/drawableWidth, (float)imageHeight/drawableHeight, 1);
        
        RenderContext ctx = {
            .viewMatrix = simdForMat(mat),
        };
        
        [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
        
        [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
        [renderEncoder setFragmentTexture:imageTxt atIndex:0];
        
//        [renderEncoder setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
//        [renderEncoder setVertexBuffer:imageRefs offset:0 atIndex:1];
//        
//        [renderEncoder setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
//        [renderEncoder setFragmentBuffer:imageBuf offset:0 atIndex:1];
//        [renderEncoder setFragmentBuffer:_selection.buf offset:0 atIndex:2];
//        [renderEncoder setFragmentTexture:_maskTexture atIndex:0];
//        [renderEncoder setFragmentTexture:_outlineTexture atIndex:1];
//        [renderEncoder setFragmentTexture:_shadowTexture atIndex:2];
//        [renderEncoder setFragmentTexture:_selectionTexture atIndex:4];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        
        [renderEncoder endEncoding];
    }
    
    
    
    
    
    
    
    
//    {
//        MTLRenderPassDescriptor* desc = [MTLRenderPassDescriptor new];
//        [[desc colorAttachments][0] setTexture:drawableTxt];
//        [[desc colorAttachments][0] setClearColor:{0,0,0,1}];
//        [[desc colorAttachments][0] setLoadAction:MTLLoadActionLoad];
//        [[desc colorAttachments][0] setStoreAction:MTLStoreActionStore];
//        id<MTLRenderCommandEncoder> enc = [_renderer.cmdBuf() renderCommandEncoderWithDescriptor:desc];
//        
//        [enc setRenderPipelineState:_pipelineState];
//        [enc setFrontFacingWinding:MTLWindingCounterClockwise];
//        [enc setCullMode:MTLCullModeNone];
//        
//        const RenderContext ctx = {
//            .viewMatrix = _Scale(.5, .5, 1),
//        };
//        
//        [enc setVertexBytes:&ctx length:sizeof(ctx) atIndex:0];
//        
//        [enc setFragmentBytes:&ctx length:sizeof(ctx) atIndex:0];
//        [enc setFragmentTexture:imageTxt atIndex:1];
//        
//        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
//        
//        [enc endEncoding];
//    }
    
    
    
    
    
//    // topInset is for handling NSWindow 'full size' content; see visibleBounds comment above
//    const size_t topInset = [drawableTxt height]-dstHeight;
//    const simd::int2 off = {
//        (simd::int1)((dstWidth-imageWidth)/2),
//        (simd::int1)topInset+(simd::int1)((dstHeight-imageHeight)/2)
//    };
//    
//    _renderer.render("MDCStudio::ImageViewShader::FragmentShader", drawableTxt,
//        // Buffer args
//        off,
//        _BackgroundColor,
//        // Texture args
//        imageTxt
//    );
    
    _renderer.present(drawable);
    _renderer.commitAndWait();
    
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
    printf("Took %ju ms\n", (uintmax_t)durationMs);
    
    
    
    
//    // topInset is for handling NSWindow 'full size' content; see visibleBounds comment above
//    const size_t topInset = [drawableTxt height]-dstHeight;
//    const simd::int2 off = {
//        (simd::int1)((dstWidth-imageWidth)/2),
//        (simd::int1)topInset+(simd::int1)((dstHeight-imageHeight)/2)
//    };
//    
//    _renderer.render("MDCStudio::ImageViewShader::FragmentShader", drawableTxt,
//        // Buffer args
//        off,
//        _BackgroundColor,
//        // Texture args
//        imageTxt
//    );
//    
//    _renderer.present(drawable);
//    _renderer.commitAndWait();
//    
//    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now()-startTime).count();
//    printf("Took %ju ms\n", (uintmax_t)durationMs);
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















@interface ImageDocumentView : NSView
@end

@implementation ImageDocumentView {
@public
    CALayer* rootLayer;
    ImageLayer* imageLayer;
}

- (void)setFrame:(NSRect)frame {
    frame.size = {2304/2, 1296/2};
//    frame.origin = {0,0};
    [super setFrame:frame];
}

//- (void)viewDidChangeBackingProperties {
//    [super viewDidChangeBackingProperties];
//    [imageLayer setContentsScale:[[self window] backingScaleFactor]];
//}
//
//- (void)viewWillStartLiveResize {
//    [super viewWillStartLiveResize];
//    [imageLayer setResizingUnderway:true];
//}
//
//- (void)viewDidEndLiveResize {
//    [super viewDidEndLiveResize];
//    [imageLayer setResizingUnderway:false];
//}

- (BOOL)isFlipped {
    return true;
}

@end

@protocol ImageScrollViewDelegate
- (void)scrollViewScrolled;
@end

@interface ImageScrollView : NSScrollView
@end

@implementation ImageScrollView {
@public
    __weak id delegate;
}

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    [delegate scrollViewScrolled];
}

@end
























@implementation ImageView {
    IBOutlet ImageScrollView* _nibView;
    IBOutlet ImageDocumentView* _documentView;
    CALayer* _rootLayer;
    ImageLayer* _imageLayer;
    __weak id<ImageViewDelegate> _delegate;
}



- (instancetype)initWithImageThumb:(const MDCStudio::ImageThumb&)imageThumb
    imageSource:(MDCStudio::ImageSourcePtr)imageSource {
    
    if (!(self = [super initWithFrame:{}])) return nil;
    
    // Make ourself layer-backed (not layer-hosted because we have to add subviews -- _nibView -- to ourself,
    // which isn't allowed when layer-hosted: "Similarly, do not add subviews to a layer-hosting view.")
    {
        [self setWantsLayer:true];
        _rootLayer = [self layer];
        
        _imageLayer = [[ImageLayer alloc] initWithImageThumb:imageThumb imageSource:imageSource];
//        [_imageLayer setActions:LayerNullActions];
//        [_imageLayer setBackgroundColor:[[[NSColor redColor] colorWithAlphaComponent:.1] CGColor]];
        [_rootLayer addSublayer:_imageLayer];
    }
    
    // Load from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        [_nibView setTranslatesAutoresizingMaskIntoConstraints:false];
        [self addSubview:_nibView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_nibView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_nibView)]];
        
        _nibView->delegate = self;
    }
    
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:false block:^(NSTimer * _Nonnull timer) {
        [_nibView setMagnification:1];
    }];
    
//    [_documentView setWantsLayer:true];
//    [[_documentView layer] setBackgroundColor:[[[NSColor redColor] colorWithAlphaComponent:.1] CGColor]];
    
//    // Configure ImageDocumentView
//    {
//        CALayer* rootLayer = [CALayer new];
//        [rootLayer setBackgroundColor:[[[NSColor redColor] colorWithAlphaComponent:.1] CGColor]];
//        
////        ImageLayer* imageLayer = [[ImageLayer alloc] initWithImageThumb:imageThumb imageSource:imageSource];
////        [rootLayer addSublayer:imageLayer];
//        
//        _documentView->rootLayer = rootLayer;
////        _documentView->imageLayer = imageLayer;
//        [_documentView setLayer:_documentView->rootLayer];
//        [_documentView setWantsLayer:true];
//    }
    
//    _layer = [[ImageLayer alloc] initWithImageThumb:imageThumb imageSource:imageSource];
//    [self setLayer:_layer];
//    [self setWantsLayer:true];
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer * _Nonnull timer) {
//        NSLog(@"ImageView: %f", [self frame].size.height);
//    }];
    
    return self;
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [_imageLayer setFrame:[_rootLayer bounds]];
    
    const CGRect bounds = [self bounds];
    const CGRect contentLayoutRect = [self convertRect:[[self window] contentLayoutRect] fromView:nil];
    _imageLayer->visibleBounds = CGRectIntersection(bounds, contentLayoutRect);
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_imageLayer setContentsScale:[[self window] backingScaleFactor]];
}

- (const ImageThumb&)imageThumb {
    return _imageLayer->imageThumb;
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

- (void)scrollViewScrolled {
    _imageLayer->scroll = [_nibView documentVisibleRect].origin;
    _imageLayer->magnification = [_nibView magnification];
    [_imageLayer setNeedsDisplay];
    NSLog(@"%@ %f", NSStringFromPoint([_nibView documentVisibleRect].origin), [_nibView magnification]);
}

@end
