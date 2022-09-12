#import "ImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "Util.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "ImageViewTypes.h"
#import "LayerScrollView.h"
#import "MetalScrollLayer.h"
using namespace MDCStudio;
using namespace MDCStudio::ImageViewTypes;
using namespace MDCTools;

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;


















@interface ImageLayer : MetalScrollLayer
@end

@implementation ImageLayer {
@public
    ImageThumb imageThumb;
    
@private
    id<MTLDevice> _device;
    id<MTLLibrary> _library;
    id<MTLCommandQueue> _commandQueue;
    
    ImagePtr _image;
    id<MTLTexture> _thumbTxt;
    id<MTLTexture> _imageTxt;
    ImageSourcePtr _imageSource;
}

- (instancetype)initWithImageThumb:(const ImageThumb&)imageThumbArg imageSource:(ImageSourcePtr)imageSource {
    if (!(self = [super init])) return nil;
    
    imageThumb = imageThumbArg;
    _imageSource = imageSource;
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    
    _library = [_device newDefaultLibrary];
    _commandQueue = [_device newCommandQueue];
    return self;
}

- (void)display {
    using namespace MDCTools;
    using namespace MDCTools::ImagePipeline;
    
    [super display];
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    // Fetch the image from the cache, if we don't have _image yet
    if (!_image) {
        __weak auto weakSelf = self;
        _image = _imageSource->imageCache()->imageForImageRef(imageThumb.ref, [=] (ImagePtr image) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf _handleImageLoaded:image]; });
        });
    }
    
    Renderer renderer(_device, _library, _commandQueue);
    
    // Create _imageTxt if it doesn't exist yet and we have the image
    if (!_imageTxt && _image) {
        Pipeline::RawImage rawImage = {
            .cfaDesc    = _image->cfaDesc,
            .width      = _image->width,
            .height     = _image->height,
            .pixels     = (ImagePixel*)(_image->data.get() + _image->off),
        };
        
        const MDCTools::Color<MDCTools::ColorSpace::Raw> illum(imageThumb.illum);
        const Pipeline::Options pipelineOpts = {
            .illum                  = illum,
//            .reconstructHighlights  = { .en = true, },
            .debayerLMMSE           = { .applyGamma = true, },
        };
        
        Pipeline::Result renderResult = Pipeline::Run(renderer, rawImage, pipelineOpts);
        _imageTxt = renderResult.txt;
    }
    
    // If we don't have the thumbnail texture yet, create it
    if (!_imageTxt && !_thumbTxt) {
        #warning TODO: try removing the Write usage flag
        _thumbTxt = renderer.textureCreate(MTLPixelFormatBGRA8Unorm, [drawableTxt width], [drawableTxt height],
            MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
        
        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
        id<MTLBuffer> thumbBuf = [renderer.dev newBufferWithBytes:imageThumb.thumb length:sizeof(imageThumb.thumb) options:BufOpts];
        const RenderThumb::Options thumbOpts = {
            .thumbWidth = ImageThumb::ThumbWidth,
            .thumbHeight = ImageThumb::ThumbHeight,
            .dataOff = 0,
        };
        RenderThumb::TextureFromRGB3(renderer, thumbOpts, thumbBuf, _thumbTxt);
    }
    
    // Finally render into `drawableTxt`, from the full-size image if it
    // exists, or the thumbnail otherwise.
    {
        id<MTLTexture> srcTxt = (_imageTxt ? _imageTxt : _thumbTxt);
        
        renderer.clear(drawableTxt, {0,0,0,0});
        
        const simd_float4x4 transform = [self transform];
        renderer.render(drawableTxt, Renderer::BlendType::None,
            renderer.VertexShader("MDCStudio::ImageViewShader::VertexShader", transform),
            renderer.FragmentShader("MDCStudio::ImageViewShader::FragmentShader", srcTxt)
        );
        
        renderer.commitAndWait();
        [drawable present];
    }
}

- (void)_handleImageLoaded:(ImagePtr)image {
    _image = image;
    [self setNeedsDisplay];
}

@end









@interface ImageDocumentView : NSView
@end

@implementation ImageDocumentView

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    const bool fit = [(LayerScrollView*)[self enclosingScrollView] magnifyToFit];
    return (fit ? CGRectInset({point, {0,0}}, -500, -500) : [self bounds]);
}

- (BOOL)isFlipped {
    return true;
}

@end



@interface ImageClipView : NSClipView
@end

@implementation ImageClipView

// -constrainBoundsRect override:
// Center the document view when it's smaller than the scroll view's bounds
- (NSRect)constrainBoundsRect:(NSRect)bounds {
    bounds = [super constrainBoundsRect:bounds];
    
    const CGSize docSize = [[self documentView] frame].size;
    if (bounds.size.width >= docSize.width) {
        bounds.origin.x = (docSize.width-bounds.size.width)/2;
    }
    if (bounds.size.height >= docSize.height) {
        bounds.origin.y = (docSize.height-bounds.size.height)/2;
    }
    return bounds;
}

@end


























constexpr CGFloat ShadowCenterOffset = 45;

@interface ImageScrollView : LayerScrollView
@end

@implementation ImageScrollView {
    NSView* _shadowView;
    CALayer* _shadowLayer;
}

static void _InitCommon(ImageScrollView* self) {
    [self setBackgroundColor:[NSColor colorWithSRGBRed:WindowBackgroundColor.srgb[0]
        green:WindowBackgroundColor.srgb[1] blue:WindowBackgroundColor.srgb[2] alpha:1]];
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    _InitCommon(self);
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _InitCommon(self);
    return self;
}

- (void)tile {
    [super tile];
    if (!_shadowView) {
        _shadowLayer = [CALayer new];
        [_shadowLayer setActions:LayerNullActions];
        NSImage* shadow = [NSImage imageNamed:@"ImageView-Shadow"];
        assert(shadow);
        [_shadowLayer setContents:shadow];
        [_shadowLayer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
        
        CGSize shadowSize = [shadow size];
        CGRect center = { ShadowCenterOffset, ShadowCenterOffset, shadowSize.width-2*ShadowCenterOffset, shadowSize.height-2*ShadowCenterOffset };
        center.origin.x /= shadowSize.width;
        center.origin.y /= shadowSize.height;
        center.size.width /= shadowSize.width;
        center.size.height /= shadowSize.height;
        [_shadowLayer setContentsCenter:center];
        
        _shadowView = [[NSView alloc] initWithFrame:{}];
        [_shadowView setTranslatesAutoresizingMaskIntoConstraints:false];
        [_shadowView setLayer:_shadowLayer];
        [_shadowView setWantsLayer:true];
        [self addSubview:_shadowView positioned:NSWindowBelow relativeTo:[self contentView]];
    }
    
    [self _updateShadowFrame];
}

- (void)_updateShadowFrame {
    NSView* docView = [self documentView];
    CGRect shadowFrame = [self convertRect:[docView visibleRect] fromView:docView];
    shadowFrame = CGRectInset(shadowFrame, -ShadowCenterOffset/[_shadowLayer contentsScale], -ShadowCenterOffset/[_shadowLayer contentsScale]);
    [_shadowView setFrame:shadowFrame];
}

- (void)reflectScrolledClipView:(NSClipView*)clipView {
    [super reflectScrolledClipView:clipView];
    [self _updateShadowFrame];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [_shadowLayer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
}

@end











@implementation ImageView {
    IBOutlet ImageScrollView* _scrollView;
    IBOutlet NSLayoutConstraint* _docWidth;
    IBOutlet NSLayoutConstraint* _docHeight;
    ImageLayer* _imageLayer;
    __weak id<ImageViewDelegate> _delegate;
}

- (instancetype)initWithImageThumb:(const MDCStudio::ImageThumb&)imageThumb
    imageSource:(MDCStudio::ImageSourcePtr)imageSource {
    
    if (!(self = [super initWithFrame:{}])) return nil;
    
    // Load from nib
    {
        [self setTranslatesAutoresizingMaskIntoConstraints:false];
        
        bool br = [[[NSNib alloc] initWithNibNamed:NSStringFromClass([self class]) bundle:nil] instantiateWithOwner:self topLevelObjects:nil];
        assert(br);
        
        [self addSubview:_scrollView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_scrollView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_scrollView]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
    }
    
//    [self setWantsLayer:true];
//    [[self layer] setBackgroundColor:[[NSColor redColor] CGColor]];
    
    _imageLayer = [[ImageLayer alloc] initWithImageThumb:imageThumb imageSource:imageSource];
    [_scrollView setScrollLayer:_imageLayer];
    
    // Set document view's size
    {
        [_docWidth setConstant:imageThumb.imageWidth*2];
        [_docHeight setConstant:imageThumb.imageHeight*2];
//        NSView* doc = [_scrollView documentView];
//        [doc setTranslatesAutoresizingMaskIntoConstraints:false];
//        [doc addConstraint:[NSLayoutConstraint constraintWithItem:doc attribute:NSLayoutAttributeWidth
//            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
//            constant:imageThumb.ref.imageWidth*2]];
//        [doc addConstraint:[NSLayoutConstraint constraintWithItem:doc attribute:NSLayoutAttributeHeight
//            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
//            constant:imageThumb.ref.imageHeight*2]];
    }
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer* timer) {
//        NSLog(@"[self bounds]: %@", NSStringFromRect([self bounds]));
//        NSLog(@"[_scrollView bounds]: %@", NSStringFromRect([_scrollView bounds]));
//        NSLog(@"[_scrollView contentView]: %@", NSStringFromRect([[_scrollView contentView] bounds]));
//        
//    }];
    
    return self;
}

- (const ImageThumb&)imageThumb {
    return _imageLayer->imageThumb;
}

- (void)setDelegate:(id<ImageViewDelegate>)delegate {
    _delegate = delegate;
}

// MARK: - Event Handling

- (void)moveLeft:(id)sender {
    [_delegate imageViewPreviousImage:self];
}

- (void)moveRight:(id)sender {
    [_delegate imageViewNextImage:self];
}

- (void)viewWillStartLiveResize {
    // MainView sends this message explicitly when resizing using the divider; forward it to _scrollView
    [super viewWillStartLiveResize];
    [_scrollView viewWillStartLiveResize];
}

- (void)viewDidEndLiveResize {
    // MainView sends this message explicitly when resizing using the divider; forward it to _scrollView
    [super viewDidEndLiveResize];
    [_scrollView viewDidEndLiveResize];
}

- (NSView*)initialFirstResponder {
    return [_scrollView documentView];
}

@end
