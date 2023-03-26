#import "ImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <thread>
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

struct _ImageLoadThreadState {
    Toastbox::Signal signal; // Protects this struct
    ImageSourcePtr imageSource;
    ImageRecordPtr work;
    std::function<void(ImageRecordPtr, Image&&)> callback;
};

@interface ImageLayer : FixedMetalDocumentLayer
@end

@implementation ImageLayer {
    NSLayoutConstraint* _width;
    NSLayoutConstraint* _height;
    
    ImageSourcePtr _imageSource;
    Renderer _renderer;
    
    ImageRecordPtr _imageRecord;
    
    struct {
        Renderer::Txt txt;
        bool txtValid = false;
    } _thumb;
    
    struct {
        Image image;
        Renderer::Txt txt;
        bool txtValid = false;
    } _image;
    
    std::shared_ptr<_ImageLoadThreadState> _imageLoad;
}

static CGColorSpaceRef _LSRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    return cs;
}

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
    NSParameterAssert(imageSource);
    if (!(self = [super init])) return nil;
    
    _imageSource = imageSource;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _renderer = Renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    [self setDevice:device];
    [self setPixelFormat:_PixelFormat];
    [self setColorspace:_LSRGBColorSpace()]; // See comment for _PixelFormat
    
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
    
    // Start our _ImageLoadThread
    {
        __weak auto selfWeak = self;
        auto imageLoad = std::make_shared<_ImageLoadThreadState>();
        imageLoad->imageSource = _imageSource;
        imageLoad->callback = [=] (ImageRecordPtr rec, Image&& image) {
            __block Image img = std::move(image);
            dispatch_async(dispatch_get_main_queue(), ^{
                [selfWeak _handleImage:rec loaded:std::move(img)];
            });
        };
        std::thread([=] { _ImageLoadThread(*imageLoad); }).detach();
        _imageLoad = imageLoad;
    }
    
    return self;
}

- (ImageRecordPtr)imageRecord {
    return _imageRecord;
}

- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec {
    NSParameterAssert(rec);
    
    _imageRecord = rec;
    _image.txtValid = false;
    _thumb.txtValid = false;
    
    // Fetch the image from the cache
    _image.image = _imageSource->getCachedImage(_imageRecord);
    // Load the image from our thread if it doesn't exist in the cache
    if (!_image.image) {
        {
            auto lock = _imageLoad->signal.lock();
            _imageLoad->work = _imageRecord;
        }
        _imageLoad->signal.signalOne();
    }
    
    assert(_width);
    assert(_height);
    [_width setConstant:_imageRecord->info.imageWidth*2];
    [_height setConstant:_imageRecord->info.imageHeight*2];
    
    [self setNeedsDisplay];
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
    
    // Nothing to do if we haven't been given an ImageRecord yet
    if (!_imageRecord) return;
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    // Create _image.txt if it doesn't exist yet and we have the image
    if (_image.image && !_image.txtValid) {
        const ImageOptions& opts = _imageRecord->options;
        
        if (!_image.txt) {
            // _image.txt: using RGBA16 (instead of RGBA8 or similar) so that we maintain a full-depth
            // representation of the pipeline result without clipping to 8-bit components, so we can
            // render to an HDR display and make use of the depth.
            _image.txt = _renderer.textureCreate(MTLPixelFormatRGBA16Float,
                _image.image.width, _image.image.height);
        }
        
        Renderer::Txt rawTxt = Pipeline::TextureForRaw(_renderer,
            _image.image.width, _image.image.height, (ImagePixel*)(_image.image.data.get()));
        
        const Pipeline::Options popts = {
            .cfaDesc                = _image.image.cfaDesc,
            
            .illum                  = ColorRaw(opts.whiteBalance.illum),
            .colorMatrix            = ColorMatrix((double*)opts.whiteBalance.colorMatrix),
            
            .defringe               = { .en = false, },
            .reconstructHighlights  = { .en = false, },
            .debayerLMMSE           = { .applyGamma = true, },
            
            .exposure               = (float)opts.exposure,
            .saturation             = (float)opts.saturation,
            .brightness             = (float)opts.brightness,
            .contrast               = (float)opts.contrast,
            
            .localContrast = {
                .en                 = (opts.localContrast.amount!=0 && opts.localContrast.radius!=0),
                .amount             = (float)opts.localContrast.amount,
                .radius             = (float)opts.localContrast.radius,
            },
        };
        
        Pipeline::Run(_renderer, popts, rawTxt, _image.txt);
        _image.txtValid = true;
    }
    
    // If we don't have the thumbnail texture yet, create it
    if (!_thumb.txtValid) {
        const size_t w = ImageThumb::ThumbWidth;
        const size_t h = ImageThumb::ThumbHeight;
        if (!_thumb.txt) {
            _thumb.txt = _renderer.textureCreate(MTLPixelFormatBC7_RGBAUnorm, w, h);
        }
        
        [_thumb.txt replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0
            slice:0 withBytes:_imageRecord->thumb.data bytesPerRow:w*4 bytesPerImage:0];
        _thumb.txtValid = true;
    }
    
    // Finally render into `drawableTxt`, from the full-size image if it
    // exists, or the thumbnail otherwise.
    {
        id<MTLTexture> srcTxt = (_image.txtValid ? _image.txt : _thumb.txt);
        
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

- (void)_handleImage:(ImageRecordPtr)rec loaded:(Image&&)image {
    if (rec != _imageRecord) return;
    _image.image = std::move(image);
    _image.txtValid = false;
    [self setNeedsDisplay];
}

// _handleImageLibraryEvent: called on whatever thread where the modification happened,
// and with the ImageLibrary lock held!
- (void)_handleImageLibraryEvent:(const ImageLibrary::Event&)ev {
    // Trampoline the event to our main thread, if we're not on the main thread
    if (![NSThread isMainThread]) {
        ImageLibrary::Event evCopy = ev;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _handleImageLibraryEvent:evCopy];
        });
        return;
    }
    
    switch (ev.type) {
    case ImageLibrary::Event::Type::Add:
        break;
    case ImageLibrary::Event::Type::Remove:
        break;
    case ImageLibrary::Event::Type::ChangeProperty:
        if (ev.records.count(_imageRecord)) {
            _thumb.txtValid = false;
            _image.txtValid = false;
            [self setNeedsDisplay];
        }
        break;
    case ImageLibrary::Event::Type::ChangeThumbnail:
        break;
    }
}

- (bool)fixedFlipped {
    return true;
}

- (void)fixedCreateConstraintsForContainer:(NSView*)container {
    _width = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
        constant:0];
    
    _height = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
        constant:0];
    
    [NSLayoutConstraint activateConstraints:@[_width, _height]];
}

//- (CGSize)preferredFrameSize {
//    if (!_imageRecord) return {};
//    return {(CGFloat)_imageRecord->info.imageWidth*2, (CGFloat)_imageRecord->info.imageHeight*2};
//}

static void _ImageLoadThread(_ImageLoadThreadState& state) {
    printf("[_ImageLoadThread] Starting\n");
    try {
        auto lock = state.signal.lock();
        
        for (;;) {
            ImageRecordPtr rec;
            
            state.signal.wait(lock, [&] { return state.work; });
            rec = std::move(state.work);
            lock.unlock();
            
            printf("[_ImageLoadThread] Load image start\n");
            Image image = state.imageSource->loadImage(ImageSource::Priority::High, rec);
            state.callback(rec, std::move(image));
            printf("[_ImageLoadThread] Load image end\n");
            
            {
                lock.lock();
                if (state.work) continue;
                lock.unlock();
                
                
            }
            
            
            {
                auto lock = state.signal.wait([&] { return state.work; });
                
                rec = std::move(state.work);
            }
            
            
        }
    
    } catch (const Toastbox::Signal::Stop&) {
    }
    printf("[_ImageLoadThread] Exiting\n");
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

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
    
    ImageLayer* imageLayer = [[ImageLayer alloc] initWithImageSource:imageSource];
    
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

- (void)setImageRecord:(ImageRecordPtr)rec {
    [_imageLayer setImageRecord:rec];
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

//- (void)fixedCreateConstraintsForContainer:(NSView*)container {
//    NSLog(@"fixedCreateConstraintsForContainer");
//}

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
