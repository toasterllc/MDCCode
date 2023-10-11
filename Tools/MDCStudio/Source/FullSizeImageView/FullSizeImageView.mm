#import "FullSizeImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <thread>
#import "Util.h"
#import "Code/Lib/Toastbox/Mac/Util.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "FixedMetalDocumentLayer.h"
#import "FullSizeImageViewTypes.h"
#import "FullSizeImageHeaderView/FullSizeImageHeaderView.h"
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
    ImageRecordPtr workNeighbors;
    std::function<void(ImageRecordPtr, Image&&)> callback;
};

@interface FullSizeImageLayer : FixedMetalDocumentLayer
@end

@implementation FullSizeImageLayer {
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

- (void)dealloc {
    printf("~FullSizeImageLayer\n");
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
    // Load the image / neighbors from our thread
    {
        {
            auto lock = _imageLoad->signal.lock();
            _imageLoad->work = (_image.image ? ImageRecordPtr{} : _imageRecord);
            _imageLoad->workNeighbors = _imageRecord;
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
            .reconstructHighlights  = { .en = opts.reconstructHighlights, },
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
    
    // Ignore if we don't have an ImageRecord
    if (!_imageRecord) return;
    
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
    [_width setActive:true];
    
    _height = [NSLayoutConstraint constraintWithItem:container attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1
        constant:0];
    [_height setActive:true];
}

//- (CGSize)preferredFrameSize {
//    if (!_imageRecord) return {};
//    return {(CGFloat)_imageRecord->info.imageWidth*2, (CGFloat)_imageRecord->info.imageHeight*2};
//}

static ImageSet _NeighborsGet(ImageLibrary& lib, ImageRecordPtr rec, size_t count) {
    // Collect the neighboring image ids in the order that we want to load them: 3 2 1 0 [img] 0 1 2 3
    auto lock = std::unique_lock(lib);
    auto find = lib.find(rec);
    auto it = find;
    auto rit = std::make_reverse_iterator(find); // Points to element before `find`
    ImageSet images;
    for (size_t i=0; i<count/2; i++) {
        if (it != lib.end()) it++;
        if (it != lib.end()) images.insert(*it);
        if (rit != lib.rend()) images.insert(*rit);
        // make_reverse_iterator() returns an iterator that points to the element _before_ the
        // forward iterator (`find`), so we increment `rit` at the end of the loop, instead of
        // at the beginning (where we increment the forward iterator `it`)
        if (rit != lib.rend()) rit++;
    }
    return images;
}

static void _ImageLoadThread(_ImageLoadThreadState& state) {
    printf("[_ImageLoadThread] Starting\n");
    try {
        ImageSource& is = *state.imageSource;
        ImageLibrary& il = is.imageLibrary();
        
        for (;;) {
            ImageRecordPtr work;
            ImageRecordPtr workNeighbors;
            {
                auto lock = state.signal.wait([&] { return state.work || state.workNeighbors; });
                work = std::move(state.work);
                workNeighbors = std::move(state.workNeighbors);
            }
            
            if (work) {
                printf("[_ImageLoadThread] Load image start\n");
                {
                    Image image = state.imageSource->loadImage(ImageSource::Priority::High, work);
                    state.callback(work, std::move(image));
                }
                printf("[_ImageLoadThread] Load image end\n");
            }
            
            if (workNeighbors) {
                printf("[_ImageLoadThread] Load neighbors start\n");
                {
                    constexpr size_t NeighborLoadCount = 4;
                    const ImageSet neighbors = _NeighborsGet(il, workNeighbors, NeighborLoadCount);
                    for (const ImageRecordPtr& rec : neighbors) {
                        {
                            auto lock = state.signal.lock();
                            if (state.work || state.workNeighbors) break;
                        }
                        
                        if (!state.imageSource->getCachedImage(rec)) {
                            state.imageSource->loadImage(ImageSource::Priority::Low, rec);
                        }
                    }
                }
                printf("[_ImageLoadThread] Load neighbors end\n");
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
//@interface FullSizeImageScrollView : LayerScrollView
//@end
//
//@implementation FullSizeImageScrollView {
//    NSView* _shadowView;
//    CALayer* _shadowLayer;
//}
//
//static void _InitCommon(FullSizeImageScrollView* self) {
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









@interface FullSizeImageDocumentView : FixedDocumentView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
@end

@implementation FullSizeImageDocumentView

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
    FullSizeImageLayer* imageLayer = [[FullSizeImageLayer alloc] initWithImageSource:imageSource];
    if (!(self = [super initWithFixedLayer:imageLayer])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
//    [NSTimer scheduledTimerWithTimeInterval:1 repeats:true block:^(NSTimer* timer) {
//        NSLog(@"[self bounds]: %@", NSStringFromRect([self bounds]));
//        NSLog(@"[_scrollView bounds]: %@", NSStringFromRect([_scrollView bounds]));
//        NSLog(@"[_scrollView contentView]: %@", NSStringFromRect([[_scrollView contentView] bounds]));
//        
//    }];
    
    return self;
}

- (void)dealloc {
    printf("~ImageView\n");
}



//- (ImageRecordPtr)imageRecord {
//    return [_imageLayer imageRecord];
//}
//
//- (void)setImageRecord:(ImageRecordPtr)rec {
//    [_imageLayer setImageRecord:rec];
//}

//- (void)setDelegate:(id<FullSizeImageViewDelegate>)delegate {
//    _delegate = delegate;
//}

//// MARK: - Event Handling
//
//- (void)moveLeft:(id)sender {
//    [_delegate fullSizeImageViewPreviousImage:self];
//}
//
//- (void)moveRight:(id)sender {
//    [_delegate fullSizeImageViewNextImage:self];
//}

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

//- (void)mouseDown:(NSEvent*)mouseDownEvent {
//    [[self window] makeFirstResponder:self];
//}

@end

@implementation FullSizeImageContainerView {
    FixedScrollView* _scrollView;
    FullSizeImageHeaderView* _headerView;
    __weak id<FullSizeImageViewDelegate> _delegate;
}

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
    if (!(self = [super initWithFrame:{}])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    {
        FullSizeImageDocumentView* doc = [[FullSizeImageDocumentView alloc] initWithImageSource:imageSource];
        _scrollView = [[FixedScrollView alloc] initWithFixedDocument:doc];
        [_scrollView setMagnifyToFit:true animate:false];
        [self addSubview:_scrollView];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_scrollView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_scrollView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
    }
    
    {
        _headerView = [[FullSizeImageHeaderView alloc] initWithFrame:{}];
        [self addSubview:_headerView];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_headerView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_headerView)]];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_headerView]"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_headerView)]];
    }
    
    return self;
}

- (MDCStudio::ImageRecordPtr)imageRecord {
    FullSizeImageLayer* layer = Toastbox::Cast<FullSizeImageLayer*>([[_scrollView document] layer]);
    return [layer imageRecord];
}

- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec {
    FullSizeImageLayer* layer = Toastbox::Cast<FullSizeImageLayer*>([[_scrollView document] layer]);
    [layer setImageRecord:rec];
}

- (void)setDelegate:(id<FullSizeImageViewDelegate>)delegate {
    _delegate = delegate;
}

// MARK: - Event Handling

- (void)moveLeft:(id)sender {
    [_delegate fullSizeImageViewPreviousImage:self];
}

- (void)moveRight:(id)sender {
    [_delegate fullSizeImageViewNextImage:self];
}

@end
