#import "DragImage.h"
#import <mutex>
#import "ImageExporter/ImageExporter.h"
#import "ImageExporter/ImageExporter.h"
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
        Toastbox::Renderer::Txt tmp = ThumbTextureForImageRecord(renderer, *selfStrong->_imageRecord);
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
    return @(ImageExporter::FileNameForImageRecord(*_imageRecord, PrefsUtil::DragAndDrop::ExportFormat()).c_str());
}

- (void)filePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider writePromiseToURL:(NSURL*)url
    completionHandler:(void(^)(NSError*))completionHandler {
    
    [_ParallelQueue() addOperationWithBlock:^{
        [self _export:url];
        completionHandler(nil);
    }];
    
//    __weak auto selfWeak = self;
//    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
////        auto selfStrong = selfWeak;
////        if (!selfStrong) return;
//        [self _export:url];
//        completionHandler(nil);
//    });
}

- (void)_export:(NSURL*)url {
    const ImageExporter::Format* fmt = PrefsUtil::DragAndDrop::ExportFormat();
    const std::filesystem::path path([url fileSystemRepresentation]);
    ImageExporter::Export(_imageSource, { _imageRecord }, fmt, path, _progressDialog);
}

- (NSOperationQueue*)operationQueueForFilePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider {
    return _SerialQueue();
}

@end
