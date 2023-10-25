#import "FullSizeImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <thread>
#import "Util.h"
#import "Code/Lib/Toastbox/Mac/Util.h"
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "FixedMetalDocumentLayer.h"
#import "FullSizeImageViewTypes.h"
#import "FullSizeImageHeaderView/FullSizeImageHeaderView.h"
#import "Calendar.h"
#import "ImagePipelineUtil.h"
#import "ImageExporter/ImageExporter.h"
using namespace MDCStudio;
using namespace MDCStudio::FullSizeImageViewTypes;
using namespace MDCTools;

// _PixelFormat == _sRGB with -setColorspace:SRGB appears to be the correct combination
// such that we supply color data in the linear SRGB colorspace and the system handles
// conversion into SRGB.
// (Without calling -setColorspace:, CAMetalLayers don't perform color matching!)
static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

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
    Object::ObserverPtr _imageLibraryOb;
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
    
    Renderer::Txt _timestampTxt;
    
    std::shared_ptr<_ImageLoadThreadState> _imageLoad;
}

static CGColorSpaceRef _SRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
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
    [self setColorspace:_SRGBColorSpace()]; // See comment for _PixelFormat
    
    // Add ourself as an observer of the image library
    {
        __weak auto selfWeak = self;
        _imageLibraryOb = _imageSource->imageLibrary()->observerAdd([=] (auto, const Object::Event& ev) {
            [selfWeak _handleImageLibraryEvent:static_cast<const ImageLibrary::Event&>(ev)];
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
    // Tell our thread to bail
    _imageLoad->signal.stop();
}

- (ImageRecordPtr)imageRecord {
    return _imageRecord;
}

- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec {
    NSParameterAssert(rec);
    
    _imageRecord = rec;
    _thumb.txtValid = false;
    _image.txtValid = false;
    _timestampTxt = {};
    
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
    [_width setConstant:_imageRecord->info.imageWidth];
    [_height setConstant:_imageRecord->info.imageHeight];
    
    [self setNeedsDisplay];
}

- (void)export:(NSWindow*)window {
    printf("_export\n");
    ImageExporter::Export(window, _imageSource, { _imageRecord });
}

static simd::float2 _TimestampOffset(ImageOptions::Corner corner, simd::float2 size) {
    using X = ImageOptions::Corner;
    switch (corner) {
    case X::BottomRight: return { 1.f-size.x, 1.f-size.y };
    case X::BottomLeft:  return {          0, 1.f-size.y };
    case X::TopLeft:     return {          0,          0 };
    case X::TopRight:    return { 1.f-size.x,          0 };
    }
    abort();
}

- (void)display {
    using namespace MDCTools;
    using namespace MDCTools::ImagePipeline;
    using namespace Toastbox;
    
    [super display];
    
    // Nothing to do if we haven't been given an ImageRecord yet
    if (!_imageRecord) return;
    
    const ImageInfo& info = _imageRecord->info;
    const ImageOptions& opts = _imageRecord->options;
    const uint16_t w = _imageRecord->info.imageWidth;
    const uint16_t h = _imageRecord->info.imageHeight;
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    // Create _image.txt if it doesn't exist yet and we have the image
    if (_image.image && !_image.txtValid) {
        if (!_image.txt) {
            // _image.txt: using RGBA16 (instead of RGBA8 or similar) so that we maintain a full-depth
            // representation of the pipeline result without clipping to 8-bit components, so we can
            // render to an HDR display and make use of the depth.
            _image.txt = _renderer.textureCreate(MTLPixelFormatRGBA16Float,
                _image.image.width, _image.image.height);
        }
        
        Renderer::Txt rawTxt = Pipeline::TextureForRaw(_renderer,
            _image.image.width, _image.image.height, (ImagePixel*)(_image.image.data.get()));
        
        Pipeline::Options popts = PipelineOptionsForImage(opts, _image.image);
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
        
        if (opts.timestamp.show && !_timestampTxt) {
            const std::string timestampStr = Calendar::TimestampString(info.timestamp);
            _timestampTxt = _TimestampTextureCreate(_renderer, @(timestampStr.c_str()));
        }
        
        _renderer.clear(drawableTxt, {0,0,0,0});
        
        const simd::float2 timestampSize = {
            (_timestampTxt ? (float)[_timestampTxt width] : 0.f) / w,
            (_timestampTxt ? (float)[_timestampTxt height] : 0.f) / h,
        };
        
        const simd::float2 timestampOffset = _TimestampOffset(opts.timestamp.corner, timestampSize);
        
        const RenderContext ctx = {
            .transform       = [self fixedTransform],
            .timestampOffset = timestampOffset,
            .timestampSize   = timestampSize,
        };
        
        _renderer.render(drawableTxt, Renderer::BlendType::None,
            _renderer.VertexShader("MDCStudio::FullSizeImageViewShader::ImageVertexShader", ctx),
            _renderer.FragmentShader("MDCStudio::FullSizeImageViewShader::FragmentShader", srcTxt)
        );
        
        // Render the timestamp if requested
        if (opts.timestamp.show) {
            _renderer.render(drawableTxt, Renderer::BlendType::None,
                _renderer.VertexShader("MDCStudio::FullSizeImageViewShader::TimestampVertexShader", ctx),
                _renderer.FragmentShader("MDCStudio::FullSizeImageViewShader::FragmentShader", _timestampTxt)
            );
        }
        
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

static Renderer::Txt _TimestampTextureCreate(Renderer& renderer, NSString* str) {
    NSAttributedString* astr = [[NSAttributedString alloc] initWithString:str attributes:@{
        NSFontAttributeName: [NSFont fontWithName:@"Helvetica Neue Light" size:48],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    }];
    
    constexpr CGFloat PaddingX = 20;
    constexpr CGFloat PaddingY = 2;
    constexpr size_t SamplesPerPixel = 4;
    constexpr size_t BytesPerSample = 1;
    const CGSize astrSize = [astr size];
    const size_t w = std::lround(astrSize.width+2*PaddingX);
    const size_t h = std::lround(astrSize.height+2*PaddingY);
    const size_t bytesPerRow = SamplesPerPixel*BytesPerSample*w;
    id /* CGColorSpaceRef */ cs = CFBridgingRelease(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
    const id /* CGContextRef */ ctx = CFBridgingRelease(CGBitmapContextCreate(nullptr, w, h, BytesPerSample*8,
        bytesPerRow, (CGColorSpaceRef)cs, kCGImageAlphaPremultipliedLast));
    
    const CGRect bounds = {{}, { (CGFloat)w, (CGFloat)h }};
//    CGContextScaleCTM((CGContextRef)ctx, contentsScale, contentsScale);
    CGContextSetRGBFillColor((CGContextRef)ctx, 0, 0, 0, 1);
    CGContextFillRect((CGContextRef)ctx, bounds);
    
    NSGraphicsContext* nsctx = [NSGraphicsContext graphicsContextWithCGContext:(CGContextRef)ctx flipped:false];
    [NSGraphicsContext setCurrentContext:nsctx];
    [astr drawAtPoint:{ PaddingX, PaddingY }];
    
    const uint8_t* samples = (const uint8_t*)CGBitmapContextGetData((CGContextRef)ctx);
    Renderer::Txt txt = renderer.textureCreate(_PixelFormat, w, h);
    renderer.textureWrite(txt, samples, SamplesPerPixel);
    return txt;
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
    case ImageLibrary::Event::Type::Remove:
    case ImageLibrary::Event::Type::Clear:
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

static ImageSet _NeighborsGet(ImageLibraryPtr lib, ImageRecordPtr rec, size_t count) {
    // Collect the neighboring image ids in the order that we want to load them: 3 2 1 0 [img] 0 1 2 3
    auto lock = std::unique_lock(*lib);
    auto find = lib->find(rec);
    auto it = find;
    auto rit = std::make_reverse_iterator(find); // Points to element before `find`
    ImageSet images;
    for (size_t i=0; i<count/2; i++) {
        if (it != lib->end()) it++;
        if (it != lib->end()) images.insert(*it);
        if (rit != lib->rend()) images.insert(*rit);
        // make_reverse_iterator() returns an iterator that points to the element _before_ the
        // forward iterator (`find`), so we increment `rit` at the end of the loop, instead of
        // at the beginning (where we increment the forward iterator `it`)
        if (rit != lib->rend()) rit++;
    }
    return images;
}

static void _ImageLoadThread(_ImageLoadThreadState& state) {
    printf("[_ImageLoadThread] Starting\n");
    try {
        ImageSourcePtr is = state.imageSource;
        ImageLibraryPtr il = is->imageLibrary();
        
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
                    Image image = is->loadImage(ImageSource::Priority::High, work);
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
                        
                        if (!is->getCachedImage(rec)) {
                            is->loadImage(ImageSource::Priority::Low, rec);
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

@interface FullSizeImageDocumentView : FixedDocumentView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
@end

@implementation FullSizeImageDocumentView

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
    FullSizeImageLayer* imageLayer = [[FullSizeImageLayer alloc] initWithImageSource:imageSource];
    if (!(self = [super initWithFixedLayer:imageLayer])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    return self;
}

- (void)dealloc {
    printf("~FullSizeImageDocumentView\n");
}

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    const bool fit = [(FixedScrollView*)[self enclosingScrollView] magnifyToFit];
    return (fit ? CGRectInset({point, {0,0}}, -500, -500) : [[self superview] bounds]);
}

@end

@interface FullSizeImageView () <FullSizeImageHeaderViewDelegate>
@end

@implementation FullSizeImageView {
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
        [self addSubview:_scrollView];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_scrollView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_scrollView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)]];
    }
    
    {
        _headerView = [[FullSizeImageHeaderView alloc] initWithFrame:{}];
        [_headerView setDelegate:self];
        [[_scrollView floatingSubviewContainer] addSubview:_headerView];
        [_scrollView setContentInsets:{[_headerView intrinsicContentSize].height+10,0,10,0}];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_headerView]|"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_headerView)]];
        
        [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_headerView]"
            options:0 metrics:nil views:NSDictionaryOfVariableBindings(_headerView)]];
    }
    
    // Create our context menu
    {
        NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
        [menu addItemWithTitle:@"Export…" action:@selector(_export:) keyEquivalent:@""];
        [self setMenu:menu];
    }
    
    [self magnifyToFit];
    return self;
}

- (void)dealloc {
    printf("~FullSizeImageView\n");
}

- (FullSizeImageLayer*)_fullSizeImageLayer {
    return Toastbox::Cast<FullSizeImageLayer*>([[_scrollView document] layer]);
}

- (MDCStudio::ImageRecordPtr)imageRecord {
    return [[self _fullSizeImageLayer] imageRecord];
}

- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec {
    [[self _fullSizeImageLayer] setImageRecord:rec];
}

- (void)setDelegate:(id<FullSizeImageViewDelegate>)delegate {
    _delegate = delegate;
}

- (void)magnifyToFit {
    [_scrollView setMagnifyToFit:true animate:false];
}

// MARK: - Event Handling

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
}

- (void)moveLeft:(id)sender {
    [_delegate fullSizeImageViewPreviousImage:self];
}

- (void)moveRight:(id)sender {
    [_delegate fullSizeImageViewNextImage:self];
}

- (void)magnifyToActualSize:(id)sender {
    [_scrollView magnifyToActualSize:sender];
}

- (void)magnifyToFit:(id)sender {
    [_scrollView magnifyToFit:sender];
}

- (void)magnifyIncrease:(id)sender {
    [_scrollView magnifyIncrease:sender];
}

- (void)magnifyDecrease:(id)sender {
    [_scrollView magnifyDecrease:sender];
}

//- (BOOL)acceptsFirstResponder {
//    return true;
//}

// MARK: - FullSizeImageHeaderViewDelegate

- (void)imageHeaderViewBack:(FullSizeImageHeaderView*)x {
    [_delegate fullSizeImageViewBack:self];
}

// MARK: - Menu Actions

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
    NSMenuItem* mitem = Toastbox::CastOrNull<NSMenuItem*>(item);
    if ([item action] == @selector(_export:)) {
        [mitem setTitle:@"Export…"];
        return true;
    } else ([item action] == @selector(_delete:)) {
        [mitem setTitle:@"Delete…"];
        return true;
    }
    return true;
}

- (IBAction)_export:(id)sender {
    printf("_export\n");
    [[self _fullSizeImageLayer] export:[self window]];
}

- (IBAction)_delete:(id)sender {
    printf("_delete\n");
    [[self _fullSizeImageLayer] export:[self window]];
}

@end
