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

// _PixelFormat: Our pixels are in the linear (LSRGB) space, and need conversion to SRGB,
// so our layer needs to have the _sRGB pixel format to enable the automatic conversion.
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;


















@interface ImageLayer : FixedMetalDocumentLayer
@end

@implementation ImageLayer {
    id<MTLDevice> _device;
    id<MTLLibrary> _library;
    id<MTLCommandQueue> _commandQueue;
    
    ImageRecordPtr _imageRecord;
    ImageSourcePtr _imageSource;
    
    std::atomic<bool> _dirty;
    ImagePtr _image;
    id<MTLTexture> _thumbTxt;
    id<MTLTexture> _imageTxt;
}

- (instancetype)initWithImageRecord:(ImageRecordPtr)imageRecord imageSource:(ImageSourcePtr)imageSource {
    if (!(self = [super init])) return nil;
    
    _imageRecord = imageRecord;
    _imageSource = imageSource;
    
    // Add ourself as an observer of the image library
    {
        auto lock = std::unique_lock(*_imageSource->imageLibrary());
        __weak auto selfWeak = self;
        _imageSource->imageLibrary()->observerAdd([=](const ImageLibrary::Event& ev) {
            auto selfStrong = selfWeak;
            if (!selfStrong) return false;
            [self _handleImageLibraryEvent:ev];
            return true;
        });
    }
    
    _device = MTLCreateSystemDefaultDevice();
    assert(_device);
    [self setDevice:_device];
    [self setPixelFormat:_PixelFormat];
    
    _library = [_device newDefaultLibrary];
    _commandQueue = [_device newCommandQueue];
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
    
    // Fetch the image from the cache, if we don't have _image yet
    if (!_image) {
        __weak auto selfWeak = self;
        _image = _imageSource->imageCache()->image(_imageRecord, [=] (ImagePtr image) {
            dispatch_async(dispatch_get_main_queue(), ^{ [selfWeak _handleImageLoaded:image]; });
        });
    }
    
    Renderer renderer(_device, _library, _commandQueue);
    
    // Create _imageTxt if it doesn't exist yet and we have the image
    if ((!_imageTxt || dirty) && _image) {
        Pipeline::RawImage rawImage = {
            .cfaDesc    = _image->cfaDesc,
            .width      = _image->width,
            .height     = _image->height,
            .pixels     = (ImagePixel*)(_image->data.get() + _image->off),
        };
        
        const MDCTools::Color<MDCTools::ColorSpace::Raw> illum(_imageRecord->info.illumEst);
        const Pipeline::Options pipelineOpts = {
            .illum = illum,
            
            .debayerLMMSE = {
                .applyGamma = true,
            },
            
            // TODO: implement
//            rotation = Rotation::None;
            .defringe = {
                .en = _imageRecord->options.defringe,
            },
            
            .reconstructHighlights = {
                .en = _imageRecord->options.reconstructHighlights,
            },
            
            // TODO: implement
//            struct [[gnu::packed]] {
//                bool show = false;
//                Corner corner = Corner::BottomRight;
//            } timestamp;
            
            
            
            .exposure = _imageRecord->options.exposure,
            .saturation = _imageRecord->options.saturation,
            .brightness = _imageRecord->options.brightness,
            .contrast = _imageRecord->options.contrast,
            .localContrast = {
                .en = false,
                .amount = _imageRecord->options.localContrast.amount,
                .radius = _imageRecord->options.localContrast.radius,
            },
        };
        
//struct [[gnu::packed]] ImageOptions {
//    enum class Rotation : uint8_t {
//        None,
//        Clockwise90,
//        Clockwise180,
//        Clockwise270,
//    };
//    
//    enum class Corner : uint8_t {
//        BottomRight,
//        BottomLeft,
//        TopLeft,
//        TopRight,
//    };
//    
//    Rotation rotation = Rotation::None;
//    bool defringe = false;
//    bool reconstructHighlights = false;
//    struct [[gnu::packed]] {
//        bool show = false;
//        Corner corner = Corner::BottomRight;
//    } timestamp;
//    uint8_t _pad[3];
//    
//    float exposure = 0;
//    float saturation = 0;
//    float brightness = 0;
//    float contrast = 0;
//    struct {
//        float amount = 0;
//        float radius = 0;
//    } localContrast;
//    
//    // _reserved: so we can add fields in the future without doing a data migration
//    uint8_t _reserved[64] = {};
//};
        
        
        
        
        
        
        
        
        Pipeline::Result renderResult = Pipeline::Run(renderer, rawImage, pipelineOpts);
        _imageTxt = renderResult.txt;
    }
    
    // If we don't have the thumbnail texture yet, create it
    if (!_thumbTxt || dirty) {
        #warning TODO: try removing the Write usage flag
        _thumbTxt = renderer.textureCreate(MTLPixelFormatBGRA8Unorm, ImageThumb::ThumbWidth, ImageThumb::ThumbHeight,
            MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
        
        const ImageLibrary::Chunk& chunk = *_imageRecord.chunk;
        constexpr MTLResourceOptions BufOpts = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
        id<MTLBuffer> thumbBuf = [renderer.dev newBufferWithBytesNoCopy:(void*)chunk.mmap.data()
            length:Mmap::PageCeil(chunk.mmap.len()) options:BufOpts deallocator:nil];
        const size_t thumbDataOff = (uintptr_t)&_imageRecord->thumb - (uintptr_t)chunk.mmap.data();
        
        const RenderThumb::Options thumbOpts = {
            .thumbWidth = ImageThumb::ThumbWidth,
            .thumbHeight = ImageThumb::ThumbHeight,
            .dataOff = thumbDataOff,
        };
        RenderThumb::TextureFromRGB3(renderer, thumbOpts, thumbBuf, _thumbTxt);
    }
    
    // Finally render into `drawableTxt`, from the full-size image if it
    // exists, or the thumbnail otherwise.
    {
        id<MTLTexture> srcTxt = (_imageTxt ? _imageTxt : _thumbTxt);
        
        renderer.clear(drawableTxt, {0,0,0,0});
        
        const simd_float4x4 transform = [self fixedTransform];
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

// _handleImageLibraryEvent: called on whatever thread where the modification happened,
// and with the ImageLibraryPtr lock held!
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
