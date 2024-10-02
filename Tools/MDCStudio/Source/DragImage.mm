#import "DragImage.h"
#import <mutex>
#import "ImageExporter/ImageExporter.h"
#import "Code/Lib/Toastbox/Signal.h"
#import "Code/Lib/Toastbox/Defer.h"
using namespace MDCStudio;

@implementation DragImage {
    ImageSourcePtr _imageSource;
    ImageRecordPtr _imageRecord;
    ImageExportProgressDialog* _progressDialog;
    NSFilePromiseProvider* _filePromise;
}

static NSOperationQueue* __QueueCreate(std::optional<size_t> concurrency=std::nullopt) {
    NSOperationQueue* x = [NSOperationQueue new];
    if (concurrency) [x setMaxConcurrentOperationCount:*concurrency];
    [x setQualityOfService:NSQualityOfServiceUserInitiated];
    return x;
}

static NSOperationQueue* _SerialQueue() {
    static NSOperationQueue* x = __QueueCreate(1);
    return x;
}

static NSOperationQueue* _ParallelQueue() {
    static NSOperationQueue* x = __QueueCreate();
    return x;
}

static int _ParallelQueueUnderwayLimit() {
    static int x = std::thread::hardware_concurrency()*2;
    return x;
}

static void _ParallelQueueUnderwayUpdate(int delta) {
    assert(delta==1 || delta==-1);
    switch (delta) {
    case 1: {
        // Don't allow too many parallel operations to accumulate, by waiting until the number
        // of queued operations falls below our threshold (_ParallelQueueUnderwayLimit).
        auto lock = _ParallelQueueState.signal.wait([] {
            return _ParallelQueueState.underway < _ParallelQueueUnderwayLimit();
        });
        _ParallelQueueState.underway++;
        break;
    }
    
    case -1: {
        auto lock = _ParallelQueueState.signal.lock();
        assert(_ParallelQueueState.underway > 0);
        _ParallelQueueState.underway--;
        _ParallelQueueState.signal.signalOne();
        break;
    }
    
    default:
        abort();
    }
}

static struct {
    Toastbox::Signal signal;
    int underway = 0;
} _ParallelQueueState;

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource
    imageRecord:(ImageRecordPtr)rec
    progressDialog:(ImageExportProgressDialog*)progressDialog
    draggingFrame:(CGRect)draggingFrame {
    
    NSFilePromiseProvider* promise = [[NSFilePromiseProvider alloc]
        initWithFileType:(id)kUTTypeDirectory delegate:self];
    
    if (!(self = [super initWithPasteboardWriter:promise])) return nil;
    _imageSource = imageSource;
    _imageRecord = rec;
    _progressDialog = progressDialog;
    
    _filePromise = promise;
    [_filePromise setDelegate:self]; // Update delegate (in case `self` changed)
    
    __weak auto selfWeak = self;
    [self setImageComponentsProvider:^NSArray<NSDraggingImageComponent*>*{
        auto selfStrong = selfWeak;
        if (!selfStrong) return nil;
        
        NSDraggingImageComponent* icon = [[NSDraggingImageComponent alloc] initWithKey:NSDraggingImageComponentIconKey];
        Toastbox::Renderer renderer;
        Toastbox::Renderer::Txt tmp = ThumbTextureForImageRecord(renderer, selfStrong->_imageRecord);
        Toastbox::Renderer::Txt thumbTxt = renderer.textureCreate(tmp, MTLPixelFormatRGBA8Unorm_sRGB);
        renderer.render(thumbTxt, tmp);
        [icon setContents:renderer.imageCreate(thumbTxt)];
        [icon setFrame:{{}, draggingFrame.size}];
        return @[icon];
    }];
    
    [self setDraggingFrame:draggingFrame];
    return self;
}

- (NSString*)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider
    fileNameForType:(NSString*)fileType {
    return @(ImageExporter::FileNameForImageRecord(*_imageRecord, &PrefsUtil::DragAndDrop::ExportFormat()).c_str());
}

- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL*)url
    completionHandler:(void(^)(NSError*))completionHandler {
    
    [_progressDialog showIfNeeded];
    
    // Short-circuit if we've been cancelled
    if ([_progressDialog canceled]) {
        completionHandler(nil);
        return;
    }
    
    _ParallelQueueUnderwayUpdate(1);
    __block Image image = _imageSource->getImage(ImageSource::Priority::Low, _imageRecord);
    [_ParallelQueue() addOperationWithBlock:^{
        [self _export:std::move(image) url:url];
        _ParallelQueueUnderwayUpdate(-1);
        completionHandler(nil);
    }];
}

- (void)_export:(Image&&)image url:(NSURL*)url {
    // Short-circuit if we've been cancelled
    if ([_progressDialog canceled]) return;
    
    const ImageExporter::Format& fmt = PrefsUtil::DragAndDrop::ExportFormat();
    const std::filesystem::path path([url fileSystemRepresentation]);
    Toastbox::Renderer renderer;
    ImageExporter::Export(renderer, *_imageRecord, image, fmt, path);
    [_progressDialog incrementProgress];
}

- (NSOperationQueue*)operationQueueForFilePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider {
    return _SerialQueue();
}

@end
