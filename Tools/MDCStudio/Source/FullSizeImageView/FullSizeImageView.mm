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
#import "ImagePipelineUtil.h"
#import "ImageExporter/ImageExporter.h"
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

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
    NSParameterAssert(imageSource);
    if (!(self = [super init])) return nil;
    
    _imageSource = imageSource;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _renderer = Toastbox::Renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
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

- (ImageRecordPtr)imageRecord {
    return _imageRecord;
}

- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec {
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
            const size_t w = ImageThumb::ThumbWidth;
            const size_t h = ImageThumb::ThumbHeight;
            Renderer::Txt thumbTxt = _renderer.textureCreate(ImageThumb::PixelFormat, w, h);
            [thumbTxt replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0
                slice:0 withBytes:_imageRecord->thumb.data bytesPerRow:w*4 bytesPerImage:0];
            
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

@interface FullSizeImageDocumentView : AnchoredDocumentView
- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource;
@end

@implementation FullSizeImageDocumentView

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
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

@end

//@interface DragImage : NSPasteboardItem
//@end
//
//@implementation DragImage
//
//- (NSPasteboardWritingOptions)writingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard {
//    NSLog(@"MEOWMIX %@", NSStringFromSelector(_cmd));
//    if ([type isEqualToString:NSPasteboardTypeFileURL]) {
//        NSLog(@"MEOWMIX returned NSPasteboardWritingPromised");
//        return NSPasteboardWritingPromised;
//    }
//    return 0;
//}
//
//@end

//@interface FilePromiseDelegate : NSObject <NSDraggingSource, NSPasteboardItemDataProvider, NSFilePromiseProviderDelegate>
//@end
//
//@implementation FilePromiseDelegate
//
//- (NSString*)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider
//    fileNameForType:(NSString*)fileType {
//    
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    
//    return [NSString stringWithFormat:@"%p.png", self];
//}
//
//- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL*)url
//    completionHandler:(void(^)(NSError*))completionHandler {
//    
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    
//    [@"hello" writeToURL:url atomically:true encoding:NSUTF8StringEncoding error:nil];
//}
//
//
//
//
//
//
//- (void)pasteboard:(NSPasteboard*)pasteboard item:(NSPasteboardItem*)item
//    provideDataForType:(NSPasteboardType)type {
//    
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    
////    if ([type isEqualToString:NSPasteboardTypeFileURL]) {
////        [pasteboard setString:@"http://apple.com" forType:NSPasteboardTypeFileURL];
//////        [pasteboard setPropertyList:@"http://apple.com" forType:NSPasteboardTypeURL];
////        return;
////    }
////    
////    abort();
//}
//
//- (void)draggingSession:(NSDraggingSession*)session willBeginAtPoint:(NSPoint)point {
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    for (NSPasteboardItem* item in [[NSPasteboard pasteboardWithName:NSPasteboardNameDrag] pasteboardItems]) {
//        NSLog(@"  MEOWMIX %@",[item types]);
//    }
//}
//
//- (void)draggingSession:(NSDraggingSession*)session endedAtPoint:(NSPoint)point
//    operation:(NSDragOperation)operation {
//    
//    NSLog(@"MEOWMIX %@ operation:%@\n", NSStringFromSelector(_cmd), @(operation));
//}
//
//- (NSDragOperation)draggingSession:(NSDraggingSession*)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
//    
//    switch(context) {
//    case NSDraggingContextOutsideApplication:   return NSDragOperationCopy;
//    case NSDraggingContextWithinApplication:
//    default:                                    return NSDragOperationNone;
//    }
//}
//
//
//@end

//@interface CustomDragImage : NSDraggingItem <NSDraggingSource, NSPasteboardItemDataProvider, NSFilePromiseProviderDelegate>
//@end
//
//@implementation CustomDragImage
//
//- (NSString*)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider
//    fileNameForType:(NSString*)fileType {
//    
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    
//    return [NSString stringWithFormat:@"%p.png", self];
//}
//
//- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL*)url
//    completionHandler:(void(^)(NSError*))completionHandler {
//    
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    
//    [@"hello" writeToURL:url atomically:true encoding:NSUTF8StringEncoding error:nil];
//}
//
//
//
//
//
//
//- (void)pasteboard:(NSPasteboard*)pasteboard item:(NSPasteboardItem*)item
//    provideDataForType:(NSPasteboardType)type {
//    
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    
////    if ([type isEqualToString:NSPasteboardTypeFileURL]) {
////        [pasteboard setString:@"http://apple.com" forType:NSPasteboardTypeFileURL];
//////        [pasteboard setPropertyList:@"http://apple.com" forType:NSPasteboardTypeURL];
////        return;
////    }
////    
////    abort();
//}
//
//- (void)draggingSession:(NSDraggingSession*)session willBeginAtPoint:(NSPoint)point {
//    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
//    for (NSPasteboardItem* item in [[NSPasteboard pasteboardWithName:NSPasteboardNameDrag] pasteboardItems]) {
//        NSLog(@"  MEOWMIX %@",[item types]);
//    }
//}
//
//- (void)draggingSession:(NSDraggingSession*)session endedAtPoint:(NSPoint)point
//    operation:(NSDragOperation)operation {
//    
//    NSLog(@"MEOWMIX %@ operation:%@\n", NSStringFromSelector(_cmd), @(operation));
//}
//
//- (NSDragOperation)draggingSession:(NSDraggingSession*)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
//    
//    switch(context) {
//    case NSDraggingContextOutsideApplication:   return NSDragOperationCopy;
//    case NSDraggingContextWithinApplication:
//    default:                                    return NSDragOperationNone;
//    }
//}
//
//@end

@interface DragImage : NSDraggingItem <NSFilePromiseProviderDelegate>
@end

@implementation DragImage {
    NSFilePromiseProvider* _filePromise;
}

- (instancetype)initDragImage {
    _filePromise = [[NSFilePromiseProvider alloc]
        initWithFileType:(id)kUTTypeDirectory delegate:self];
    
    if (!(self = [super initWithPasteboardWriter:_filePromise])) return nil;
    
    // Update delegate in case `self` changed
    [_filePromise setDelegate:self];
    return self;
}

- (NSString*)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider
    fileNameForType:(NSString*)fileType {
    
    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
    
    return [NSString stringWithFormat:@"%p.png", self];
}

- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL*)url
    completionHandler:(void(^)(NSError*))completionHandler {
    
    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
    
    [@"hello" writeToURL:url atomically:true encoding:NSUTF8StringEncoding error:nil];
    completionHandler(nil);
}

@end

@interface FullSizeImageView () <FullSizeImageHeaderViewDelegate, NSDraggingSource>
@end

@implementation FullSizeImageView {
    AnchoredScrollView* _scrollView;
    FullSizeImageHeaderView* _headerView;
    Object::ObserverPtr _prefsOb;
    DragImage* _dragImage;
}

- (instancetype)initWithImageSource:(MDCStudio::ImageSourcePtr)imageSource {
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

- (MDCStudio::ImageRecordPtr)imageRecord {
    return [[self _fullSizeImageLayer] imageRecord];
}

- (void)setImageRecord:(MDCStudio::ImageRecordPtr)rec {
    [[self _fullSizeImageLayer] setImageRecord:rec];
}

- (void)_prefsChanged {
    [[self _fullSizeImageLayer] rerender];
}

- (void)magnifyToFit {
    [_scrollView setMagnifyToFit:true animate:false];
}

// MARK: - Event Handling

- (NSString*)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider
    fileNameForType:(NSString*)fileType {
    
    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
    
    return [NSString stringWithFormat:@"%p.png", self];
}

- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL*)url
    completionHandler:(void(^)(NSError*))completionHandler {
    
    NSLog(@"MEOWMIX %@\n", NSStringFromSelector(_cmd));
    
    [@"hello" writeToURL:url atomically:true encoding:NSUTF8StringEncoding error:nil];
}

- (void)mouseDown:(NSEvent*)event {
    [[self window] makeFirstResponder:self];
    
//    NSFilePromiseProvider* filePromise = [[NSFilePromiseProvider alloc]
//        initWithFileType:(id)kUTTypeDirectory
//        delegate:self];
    
//    DragImage* item = [DragImage new];
//    [item setDataProvider:self forTypes:@[
//        NSPasteboardTypeFileURL,
////        (id)kUTTypeImage,
////        (id)kUTTypeJPEG, (id)kUTTypePNG, (id)kUTTypeRawImage,
//    ]];
    
//    [item setDataProvider:self forTypes:@[
//        (id)kUTTypeJPEG, (id)kUTTypePNG, (id)kUTTypeRawImage, (id)kUTTypeFileURL,
//    ]];
    
// kUTTypeJPEG
// kUTTypePNG
// kUTTypeRawImage
    
    _dragImage = [[DragImage alloc] initDragImage];
    
//    static id <NSFilePromiseProviderDelegate> delegate = [FilePromiseDelegate new];
//    NSFilePromiseProvider* filePromise = [NSFilePromiseProvider new];
//    CustomDragImage* dragItem = [[CustomDragImage alloc] initWithPasteboardWriter:filePromise];
//    [filePromise setFileType:(id)kUTTypeDirectory];
//    [filePromise setDelegate:self];
//    [filePromise setDelegate:dragItem];
//    [filePromise setDelegate:delegate];
    
//    NSFilePromiseProvider* filePromise = [[NSFilePromiseProvider alloc]
//        initWithFileType:(id)kUTTypeDirectory
//        delegate:self];
//    NSDraggingItem* dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:filePromise];
    
    CGPoint dragPosition = [self convertPoint:[event locationInWindow] fromView:nil];
//    dragPosition.x -= self.image.size.width/5/2;
//    dragPosition.y -= self.image.size.height/5/2;
//    CGRect draggingRect = NSMakeRect(dragPosition.x, dragPosition.y, self.image.size.width/5, self.image.size.height/5);
    [_dragImage setDraggingFrame:{dragPosition, {10,10}}];
//    [dragItem setDraggingFrame:{dragPosition, {10,10}} contents:self.image];
    
    
    NSLog(@"MEOWMIX called beginDraggingSessionWithItems");
    [self beginDraggingSessionWithItems:@[_dragImage] event:event source:self];
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

// MARK: - Drag & Drop

- (void)draggingSession:(NSDraggingSession*)session endedAtPoint:(NSPoint)point
    operation:(NSDragOperation)operation {
    
    _dragImage = nullptr;
}

- (NSDragOperation)draggingSession:(NSDraggingSession*)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    
    switch(context) {
    case NSDraggingContextOutsideApplication:   return NSDragOperationCopy;
    case NSDraggingContextWithinApplication:
    default:                                    return NSDragOperationNone;
    }
}

@end
