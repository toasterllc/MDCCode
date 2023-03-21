#import "ImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "Util.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "FixedMetalDocumentLayer.h"
#import "ImageViewTypes.h"
using namespace MDCStudio;
using namespace MDCStudio::ImageViewTypes;
using namespace MDCTools;

// _PixelFormat: Our pixels are in the linear RGB space (LSRGB), and need conversion to the display color space.
// To do so, we declare that our pixels are LSRGB (ie we _don't_ use the _sRGB MTLPixelFormat variant!),
// and we opt-in to color matching by setting the colorspace on our CAMetalLayer via -setColorspace:.
// (Without calling -setColorspace:, CAMetalLayers don't perform color matching!)
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm;

@interface ImageLayer : FixedMetalDocumentLayer
@end

@implementation ImageLayer {
    ImageRecordPtr _imageRecord;
    ImageSourcePtr _imageSource;
    Renderer _renderer;
    
    std::atomic<bool> _dirty;
    ImagePtr _image;
    Renderer::Txt _thumbTxt;
    Renderer::Txt _imageTxt;
}

static CGColorSpaceRef _LSRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    return cs;
}

- (instancetype)initWithImageRecord:(ImageRecordPtr)imageRecord imageSource:(ImageSourcePtr)imageSource {
    if (!(self = [super init])) return nil;
    
    _imageRecord = imageRecord;
    _imageSource = imageSource;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _renderer = Renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    // Add ourself as an observer of the image library
    {
        auto lock = std::unique_lock(_imageSource->imageLibrary());
        __weak auto selfWeak = self;
        _imageSource->imageLibrary().observerAdd([=](const ImageLibrary::Event& ev) {
            auto selfStrong = selfWeak;
            if (!selfStrong) return false;
            [selfStrong _handleImageLibraryEvent:ev];
            return true;
        });
    }
    
    [self setDevice:device];
    [self setPixelFormat:_PixelFormat];
    [self setColorspace:_LSRGBColorSpace()]; // See comment for _PixelFormat
    return self;
}

- (ImageRecordPtr)imageRecord {
    return _imageRecord;
}

//static id<MTLTexture> _ThumbRender(Renderer& renderer, const ImageRecord& thumb) {
//    using namespace MDCTools;
//    using namespace MDCTools::ImagePipeline;
//    
//    #warning TODO: try removing the Write usage flag
//    id<MTLTexture> txt = renderer.textureCreate(MTLPixelFormatBGRA8Unorm, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight,
//        MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
//    
//    constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeManaged;
//    id<MTLBuffer> thumbBuf = [renderer.dev newBufferWithBytes:thumb.thumb length:sizeof(thumb.thumb) options:BufOpts];
//    const RenderThumb::Options thumbOpts = {
//        .thumbWidth = ImageThumb::ThumbWidth,
//        .thumbHeight = ImageThumb::ThumbHeight,
//        .dataOff = 0,
//    };
//    RenderThumb::TextureFromRGB3(renderer, thumbOpts, thumbBuf, txt);
//    
//    return txt;
//}

- (void)display {
    using namespace MDCTools;
    using namespace MDCTools::ImagePipeline;
    using namespace Toastbox;
    
    [super display];
    
    const bool dirty = _dirty.exchange(false);
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
//    // Fetch the image from the cache, if we don't have _image yet
//    if (!_image) {
//        __weak auto selfWeak = self;
//        _image = _imageSource->imageCache().image(_imageRecord, [=] (ImagePtr image) {
//            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _handleImageLoaded:image]; });
//        });
//    }
    
//    // Create _imageTxt if it doesn't exist yet and we have the image
//    if ((!_imageTxt || dirty) && _image) {
//        const ImageOptions& opts = _imageRecord->options;
//        
//        if (!_imageTxt) {
//            // _imageTxt: using RGBA16 (instead of RGBA8 or similar) so that we maintain a full-depth
//            // representation of the pipeline result without clipping to 8-bit components, so we can
//            // render to an HDR display and make use of the depth.
//            _imageTxt = _renderer.textureCreate(MTLPixelFormatRGBA16Float, _image->width, _image->height);
//        }
//        
//        Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
//            _image->width, _image->height, (ImagePixel*)(_image->data.get() + _image->off));
//        
//        const Pipeline::Options popts = {
//            .cfaDesc                = _image->cfaDesc,
//            
//            .illum                  = ColorRaw(opts.whiteBalance.illum),
//            .colorMatrix            = ColorMatrix((double*)opts.whiteBalance.colorMatrix),
//            
//            .defringe               = { .en = false, },
//            .reconstructHighlights  = { .en = false, },
//            .debayerLMMSE           = { .applyGamma = true, },
//            
//            .exposure               = (float)opts.exposure,
//            .saturation             = (float)opts.saturation,
//            .brightness             = (float)opts.brightness,
//            .contrast               = (float)opts.contrast,
//            
//            .localContrast = {
//                .en                 = (opts.localContrast.amount!=0 && opts.localContrast.radius!=0),
//                .amount             = (float)opts.localContrast.amount,
//                .radius             = (float)opts.localContrast.radius,
//            },
//        };
//        
//        Pipeline::Run(renderer, popts, rawTxt, _imageTxt);
//    }
    
    // If we don't have the thumbnail texture yet, create it
    if (!_thumbTxt || dirty) {
        if (!_thumbTxt) {
            _thumbTxt = _renderer.textureCreate(MTLPixelFormatBC7_RGBAUnorm, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight);
        }
        
        [_thumbTxt replaceRegion:MTLRegionMake2D(0,0,ImageThumb::ThumbWidth,ImageThumb::ThumbHeight) mipmapLevel:0
            slice:0 withBytes:_imageRecord->thumb.data bytesPerRow:ImageThumb::ThumbWidth*4 bytesPerImage:0];
    }
    
    // Finally render into `drawableTxt`, from the full-size image if it
    // exists, or the thumbnail otherwise.
    {
        id<MTLTexture> srcTxt = (_imageTxt ? _imageTxt : _thumbTxt);
        
        _renderer.clear(drawableTxt, {0,0,0,0});
        
        const simd_float4x4 transform = [self fixedTransform];
        _renderer.render(drawableTxt, Renderer::BlendType::None,
            _renderer.VertexShader("MDCStudio::ImageViewShader::VertexShader", transform),
            _renderer.FragmentShader("MDCStudio::ImageViewShader::FragmentShader", srcTxt)
        );
        
        _renderer.commitAndWait();
        [drawable present];
    }
}

- (void)_handleImageLoaded:(ImagePtr)image {
    _image = image;
    [self setNeedsDisplay];
}

// _handleImageLibraryEvent: called on whatever thread where the modification happened,
// and with the ImageLibrary lock held!
- (void)_handleImageLibraryEvent:(const ImageLibrary::Event&)ev {
    switch (ev.type) {
    case ImageLibrary::Event::Type::Add:
        break;
    case ImageLibrary::Event::Type::Remove:
        break;
    case ImageLibrary::Event::Type::Change:
        if (ev.records.count(_imageRecord)) {
            _dirty = true;
            dispatch_async(dispatch_get_main_queue(), ^{ [self setNeedsDisplay]; });
        }
        break;
    }
}

- (bool)fixedFlipped {
    return true;
}

- (CGSize)preferredFrameSize {
    return {(CGFloat)_imageRecord->info.imageWidth*2, (CGFloat)_imageRecord->info.imageHeight*2};
}

@end









//@interface ImageDocumentView : NSView
//@end
//
//@implementation ImageDocumentView
//
//- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
//    const bool fit = [(LayerScrollView*)[self enclosingScrollView] magnifyToFit];
//    return (fit ? CGRectInset({point, {0,0}}, -500, -500) : [self bounds]);
//}
//
//- (BOOL)isFlipped {
//    return true;
//}
//
//@end



//@interface ImageClipView : NSClipView
//@end
//
//@implementation ImageClipView
//
//// -constrainBoundsRect override:
//// Center the document view when it's smaller than the scroll view's bounds
//- (NSRect)constrainBoundsRect:(NSRect)bounds {
//    bounds = [super constrainBoundsRect:bounds];
//    
//    const CGSize docSize = [[self documentView] frame].size;
//    if (bounds.size.width >= docSize.width) {
//        bounds.origin.x = (docSize.width-bounds.size.width)/2;
//    }
//    if (bounds.size.height >= docSize.height) {
//        bounds.origin.y = (docSize.height-bounds.size.height)/2;
//    }
//    return bounds;
//}
//
//@end


























//constexpr CGFloat ShadowCenterOffset = 45;
//
//@interface ImageScrollView : LayerScrollView
//@end
//
//@implementation ImageScrollView {
//    NSView* _shadowView;
//    CALayer* _shadowLayer;
//}
//
//static void _InitCommon(ImageScrollView* self) {
//    [self setBackgroundColor:[NSColor colorWithSRGBRed:WindowBackgroundColor.srgb[0]
//        green:WindowBackgroundColor.srgb[1] blue:WindowBackgroundColor.srgb[2] alpha:1]];
//}
//
//- (instancetype)initWithCoder:(NSCoder*)coder {
//    if (!(self = [super initWithCoder:coder])) return nil;
//    _InitCommon(self);
//    return self;
//}
//
//- (instancetype)initWithFrame:(NSRect)frame {
//    if (!(self = [super initWithFrame:frame])) return nil;
//    _InitCommon(self);
//    return self;
//}
//
//- (void)tile {
//    [super tile];
//    if (!_shadowView) {
//        _shadowLayer = [CALayer new];
//        [_shadowLayer setActions:LayerNullActions];
//        NSImage* shadow = [NSImage imageNamed:@"ImageView-Shadow"];
//        assert(shadow);
//        [_shadowLayer setContents:shadow];
//        [_shadowLayer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
//        
//        CGSize shadowSize = [shadow size];
//        CGRect center = { ShadowCenterOffset, ShadowCenterOffset, shadowSize.width-2*ShadowCenterOffset, shadowSize.height-2*ShadowCenterOffset };
//        center.origin.x /= shadowSize.width;
//        center.origin.y /= shadowSize.height;
//        center.size.width /= shadowSize.width;
//        center.size.height /= shadowSize.height;
//        [_shadowLayer setContentsCenter:center];
//        
//        _shadowView = [[NSView alloc] initWithFrame:{}];
//        [_shadowView setTranslatesAutoresizingMaskIntoConstraints:false];
//        [_shadowView setLayer:_shadowLayer];
//        [_shadowView setWantsLayer:true];
//        [self addSubview:_shadowView positioned:NSWindowBelow relativeTo:[self contentView]];
//    }
//    
//    [self _updateShadowFrame];
//}
//
//- (void)_updateShadowFrame {
//    NSView* docView = [self documentView];
//    CGRect shadowFrame = [self convertRect:[docView visibleRect] fromView:docView];
//    shadowFrame = CGRectInset(shadowFrame, -ShadowCenterOffset/[_shadowLayer contentsScale], -ShadowCenterOffset/[_shadowLayer contentsScale]);
//    [_shadowView setFrame:shadowFrame];
//}
//
//- (void)reflectScrolledClipView:(NSClipView*)clipView {
//    [super reflectScrolledClipView:clipView];
//    [self _updateShadowFrame];
//}
//
//- (void)viewDidChangeBackingProperties {
//    [super viewDidChangeBackingProperties];
//    [_shadowLayer setContentsScale:std::max(1., [[self window] backingScaleFactor])];
//}
//
//@end











@implementation ImageView {
    ImageLayer* _imageLayer;
    __weak id<ImageViewDelegate> _delegate;
}

- (instancetype)initWithImageRecord:(ImageRecordPtr)imageRecord imageSource:(ImageSourcePtr)imageSource {
    
    ImageLayer* imageLayer = [[ImageLayer alloc] initWithImageRecord:imageRecord imageSource:imageSource];
    
    if (!(self = [super initWithFixedLayer:imageLayer])) return nil;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    _imageLayer = imageLayer;
    
//    // Set document view's size
//    {
//        [_docWidth setConstant:imageThumb.imageWidth*2];
//        [_docHeight setConstant:imageThumb.imageHeight*2];
////        NSView* doc = [_scrollView documentView];
////        [doc setTranslatesAutoresizingMaskIntoConstraints:false];
////        [doc addConstraint:[NSLayoutConstraint constraintWithItem:doc attribute:NSLayoutAttributeWidth
////            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
////            constant:imageThumb.ref.imageWidth*2]];
////        [doc addConstraint:[NSLayoutConstraint constraintWithItem:doc attribute:NSLayoutAttributeHeight
////            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
////            constant:imageThumb.ref.imageHeight*2]];
//    }
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer* timer) {
//        NSLog(@"[self bounds]: %@", NSStringFromRect([self bounds]));
//        NSLog(@"[_scrollView bounds]: %@", NSStringFromRect([_scrollView bounds]));
//        NSLog(@"[_scrollView contentView]: %@", NSStringFromRect([[_scrollView contentView] bounds]));
//        
//    }];
    
    return self;
}

- (ImageRecordPtr)imageRecord {
    return [_imageLayer imageRecord];
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

//- (void)viewWillStartLiveResize {
//    // MainView sends this message explicitly when resizing using the divider; forward it to _scrollView
//    [super viewWillStartLiveResize];
//    [_scrollView viewWillStartLiveResize];
//}
//
//- (void)viewDidEndLiveResize {
//    // MainView sends this message explicitly when resizing using the divider; forward it to _scrollView
//    [super viewDidEndLiveResize];
//    [_scrollView viewDidEndLiveResize];
//}

//- (NSView*)initialFirstResponder {
//    return [_scrollView documentView];
//}

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    const bool fit = [(FixedScrollView*)[self enclosingScrollView] magnifyToFit];
    return (fit ? CGRectInset({point, {0,0}}, -500, -500) : [self bounds]);
}

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
}

//// MARK: - NSView Overrides
//- (void)fixedCreateConstraintsForContainer:(NSView*)container {
//    
////        [_docWidth setConstant:imageThumb.imageWidth*2];
////        [_docHeight setConstant:imageThumb.imageHeight*2];
//////        NSView* doc = [_scrollView documentView];
//////        [doc setTranslatesAutoresizingMaskIntoConstraints:false];
//////        [doc addConstraint:[NSLayoutConstraint constraintWithItem:doc attribute:NSLayoutAttributeWidth
//////            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
//////            constant:imageThumb.ref.imageWidth*2]];
//////        [doc addConstraint:[NSLayoutConstraint constraintWithItem:doc attribute:NSLayoutAttributeHeight
//////            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
//////            constant:imageThumb.ref.imageHeight*2]];
//    
//    NSLayoutConstraint* width = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeWidth
//        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
//        constant:_imageLayer->imageThumb.imageWidth*2];
//    
//    NSLayoutConstraint* height = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
//        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
//        constant:_imageLayer->imageThumb.imageHeight*2];
//    
//    [NSLayoutConstraint activateConstraints:@[width, height]];
//}

@end

@implementation ImageScrollView

//- (NSView*)initialFirstResponder {
//    return [self document];
//}

@end
