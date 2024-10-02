#import "FullSizeImageView.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <thread>
#import "Util.h"
#import "Code/Lib/Toastbox/Mac/Util.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"
#import "Code/Lib/AnchoredScrollView/AnchoredMetalDocumentLayer.h"
#import "Tools/Shared/ImagePipeline/RenderThumb.h"
#import "Tools/Shared/ImagePipeline/ImagePipeline.h"
#import "FullSizeImageViewTypes.h"
#import "FullSizeImageHeaderView/FullSizeImageHeaderView.h"
#import "ImageUtil.h"
#import "ImagePipelineUtil.h"
#import "ImageExporter/ImageExporter.h"
#import "DragImage.h"
using namespace MDCStudio;
using namespace MDCStudio::FullSizeImageViewTypes;

struct _ImageLoadThreadState {
    Toastbox::Signal signal; // Protects this struct
    ImageSourcePtr imageSource;
    ImageRecordPtr work;
    ImageRecordPtr workNeighbors;
    std::function<void(ImageRecordPtr, Image&&)> callback;
};

@interface FullSizeImageLayer : AnchoredMetalDocumentLayer
@end

@implementation FullSizeImageLayer {
    NSLayoutConstraint* _width;
    NSLayoutConstraint* _height;
    
    ImageSourcePtr _imageSource;
    Object::ObserverPtr _imageLibraryOb;
    Toastbox::Renderer _renderer;
    
    ImageRecordPtr _imageRecord;
    
    struct {
        Image image;
        Toastbox::Renderer::Txt txt;
        bool txtValid = false;
    } _image;
    
    std::shared_ptr<_ImageLoadThreadState> _imageLoad;
}

static CGColorSpaceRef _LinearSRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
    return cs;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    NSParameterAssert(imageSource);
    if (!(self = [super init])) return nil;
    
    _imageSource = imageSource;
    
    [self setDevice:[self preferredDevice]];
    [self setColorspace:_LinearSRGBColorSpace()];
    [self setOpaque:false];
    
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

- (ImageSourcePtr)imageSource {
    return _imageSource;
}

- (ImageRecordPtr)imageRecord {
    return _imageRecord;
}

- (void)setImageRecord:(ImageRecordPtr)rec {
    NSParameterAssert(rec);
    
    _imageRecord = rec;
    
    // Fetch the image from the cache
    _image.image = _imageSource->getImage(ImageSource::Priority::Cache, _imageRecord);
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
    [self rerender];
}

- (void)display {
    using namespace ImagePipeline;
    using namespace Toastbox;
    
    [super display];
    
    // Nothing to do if we haven't been given an ImageRecord yet
    if (!_imageRecord) return;
    
    id<CAMetalDrawable> drawable = [self nextDrawable];
    assert(drawable);
    id<MTLTexture> drawableTxt = [drawable texture];
    assert(drawableTxt);
    
    if (!_image.txt) {
        // _image.txt: using RGBA16 (instead of RGBA8 or similar) so that we maintain a full-depth
        // representation of the pipeline result without clipping to 8-bit components, so we can
        // render to an HDR display and make use of the depth.
        _image.txt = _renderer.textureCreate(MTLPixelFormatRGBA16Float,
            _imageRecord->info.imageWidth, _imageRecord->info.imageHeight);
    }
    
    if (!_image.txtValid) {
        Pipeline::Options popts = PipelineOptionsForImage(*_imageRecord, _image.image);
        // Create _image.txt if it doesn't exist yet and we have the image
        if (_image.image) {
            Renderer::Txt rawTxt = Pipeline::TextureForRaw(_renderer,
                _image.image.width, _image.image.height, (Img::Pixel*)(_image.image.data.get()));
            
            Pipeline::Run(_renderer, popts, rawTxt, _image.txt);
            
//            _renderer.debugTextureShow(rawTxt);
        
        } else {
            Renderer::Txt thumbTxt = ThumbTextureForImageRecord(_renderer, _imageRecord);
            _renderer.render(_image.txt, thumbTxt);
            if (!popts.timestamp.string.empty()) {
                Pipeline::TimestampOverlayRender(_renderer, popts.timestamp, _image.txt);
            }
        }
        
        _image.txtValid = true;
    }
    
    // Finally render into `drawableTxt`, from the full-size image if it
    // exists, or the thumbnail otherwise.
    {
        _renderer.clear(drawableTxt, {0,0,0,0});
        
        const RenderContext ctx = {
            .transform = [self anchoredTransform],
        };
        
        _renderer.render(drawableTxt, Renderer::BlendType::None,
            _renderer.VertexShader("MDCStudio::FullSizeImageViewShader::ImageVertexShader", ctx),
            _renderer.FragmentShader("MDCStudio::FullSizeImageViewShader::FragmentShader", _image.txt)
        );
        
        _renderer.commitAndWait();
        [drawable present];
    }
}

- (void)rerender {
    _image.txtValid = false;
    [self setNeedsDisplay];
}

- (void)_handleImage:(ImageRecordPtr)rec loaded:(Image&&)image {
    if (rec != _imageRecord) return;
    _image.image = std::move(image);
    [self rerender];
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
            [self rerender];
        }
        break;
    case ImageLibrary::Event::Type::ChangeThumbnail:
        break;
    }
}

- (void)anchoredCreateConstraintsForContainer:(NSView*)container {
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
                    Image image = is->getImage(ImageSource::Priority::High, work);
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
                        
                        is->getImage(ImageSource::Priority::Low, rec);
                    }
                }
                printf("[_ImageLoadThread] Load neighbors end\n");
            }
        }
    
    } catch (const Toastbox::Signal::Stop&) {
        printf("[_ImageLoadThread] STOPPED\n");
    }
    printf("[_ImageLoadThread] Exiting\n");
}

@end

@interface FullSizeImageDocumentView : AnchoredDocumentView <NSDraggingSource>
- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource;
@end

@implementation FullSizeImageDocumentView {
    struct {
        NSDraggingSession* session;
        DragImage* image;
    } _drag;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    FullSizeImageLayer* imageLayer = [[FullSizeImageLayer alloc] initWithImageSource:imageSource];
    if (!(self = [super initWithAnchoredLayer:imageLayer])) return nil;
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    return self;
}

- (void)dealloc {
    printf("~FullSizeImageDocumentView\n");
}

- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)point inRect:(NSRect)rect {
    const bool fit = [(AnchoredScrollView*)[self enclosingScrollView] magnifyToFit];
    return (fit ? CGRectInset({point, {0,0}}, -500, -500) : [[self superview] bounds]);
}
// MARK: - Event Handling

- (void)mouseDown:(NSEvent*)mouseDownEvent {
    [[self window] makeFirstResponder:self];
    
    NSWindow* win = [self window];
    FullSizeImageLayer* layer = (FullSizeImageLayer*)[self layer];
    ImageRecordPtr rec = [layer imageRecord];
    const ImageLibrary::Descriptor& desc = ImageLibrary::DescriptorForRecordSize(rec.recordSize);
    const CGPoint mouseDownPoint = [self convertPoint:[mouseDownEvent locationInWindow] fromView:nil];
    Toastbox::TrackMouse(win, mouseDownEvent, [&] (NSEvent* event, bool done) {
        constexpr CGFloat DragThreshold = 5;
        const CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
        const CGFloat dist = std::hypot(point.x-mouseDownPoint.x, point.y-mouseDownPoint.y);
        if (dist < DragThreshold) return true; // Continue tracking mouse
        
        NSView* dragView = [[self enclosingScrollView] superview];
        CGPoint dragPosition = [dragView convertPoint:[event locationInWindow] fromView:nil];
        CGRect draggingFrame = {{}, {(CGFloat)desc.thumbWidth/2, (CGFloat)desc.thumbHeight/2}};
        draggingFrame.origin = {
            dragPosition.x - draggingFrame.size.width/2,
            dragPosition.y - draggingFrame.size.height/2,
        };
        
        _drag.image = [[DragImage alloc] initWithImageSource:[layer imageSource]
            imageRecord:[layer imageRecord]
            progressDialog:nil
            draggingFrame:draggingFrame];
        
        _drag.session = [dragView beginDraggingSessionWithItems:@[_drag.image] event:event source:self];
        [_drag.session setDraggingFormation:NSDraggingFormationPile];
        // Stop tracking mouse; this is apparently necessary becuase recursive mouse
        // tracking isn't compatible with -beginDraggingSessionWithItems:.
        return false;
    });
}

// MARK: - Drag & Drop

- (NSDragOperation)draggingSession:(NSDraggingSession*)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    
    switch(context) {
    case NSDraggingContextOutsideApplication:   return NSDragOperationCopy;
    case NSDraggingContextWithinApplication:
    default:                                    return NSDragOperationNone;
    }
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    _drag = {};
}

@end

@interface FullSizeImageView () <FullSizeImageHeaderViewDelegate>
@end

@implementation FullSizeImageView {
    AnchoredScrollView* _scrollView;
    FullSizeImageHeaderView* _headerView;
    Object::ObserverPtr _prefsOb;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource {
    if (!(self = [super initWithFrame:{}])) return nil;
    __weak auto selfWeak = self;
    
    [self setTranslatesAutoresizingMaskIntoConstraints:false];
    
    {
        FullSizeImageDocumentView* doc = [[FullSizeImageDocumentView alloc] initWithImageSource:imageSource];
        _scrollView = [[AnchoredScrollView alloc] initWithAnchoredDocument:doc];
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
    
    {
        _prefsOb = PrefsGlobal()->observerAdd([=] (auto, auto) { [selfWeak _prefsChanged]; });
    }
    
    [self magnifyToFit];
    return self;
}

- (void)dealloc {
    printf("~FullSizeImageView\n");
}

- (IBAction)print:(id)sender {
    [[NSPrintOperation printOperationWithView:self] runOperation];
}

- (FullSizeImageLayer*)_fullSizeImageLayer {
    return Toastbox::Cast<FullSizeImageLayer*>([[_scrollView document] layer]);
}

- (ImageSourcePtr)imageSource {
    return [[self _fullSizeImageLayer] imageSource];
}

- (ImageRecordPtr)imageRecord {
    return [[self _fullSizeImageLayer] imageRecord];
}

- (void)setImageRecord:(ImageRecordPtr)rec {
    [[self _fullSizeImageLayer] setImageRecord:rec];
}

- (void)_prefsChanged {
    [[self _fullSizeImageLayer] rerender];
}

- (void)magnifyToFit {
    [_scrollView setMagnifyToFit:true animate:false];
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

// MARK: - FullSizeImageHeaderViewDelegate

- (void)imageHeaderViewBack:(FullSizeImageHeaderView*)x {
    [[self window] tryToPerform:@selector(_backToImages:) with:self];
}

@end
