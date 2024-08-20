#import "DragImage.h"
#import "ImageExporter/ImageExporter.h"
#import "ImageExporter/ImageExporter.h"
using namespace MDCStudio;

@implementation DragImage {
    ImageSourcePtr _imageSource;
    ImageRecordPtr _imageRecord;
    ImageExportProgressDialog* _progressDialog;
    NSOperationQueue* _queue;
    NSFilePromiseProvider* _filePromise;
}

- (instancetype)initWithImageSource:(ImageSourcePtr)imageSource
    imageRecord:(ImageRecordPtr)rec
    progressDialog:(ImageExportProgressDialog*)progressDialog
    operationQueue:(NSOperationQueue*)queue
    draggingFrame:(CGRect)draggingFrame {
    
    NSFilePromiseProvider* promise = [[NSFilePromiseProvider alloc]
        initWithFileType:(id)kUTTypeDirectory delegate:self];
    
    if (!(self = [super initWithPasteboardWriter:promise])) return nil;
    _imageSource = imageSource;
    _imageRecord = rec;
    _progressDialog = progressDialog;
    
    _queue = queue;
    
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
    
//    __weak auto selfWeak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
//        auto selfStrong = selfWeak;
//        if (!selfStrong) return;
        [self _export:url];
        completionHandler(nil);
    });
}

- (void)_export:(NSURL*)url {
    const ImageExporter::Format* fmt = PrefsUtil::DragAndDrop::ExportFormat();
    const std::filesystem::path path([url fileSystemRepresentation]);
    ImageExporter::Export(_imageSource, { _imageRecord }, fmt, path, _progressDialog);
}

- (NSOperationQueue*)operationQueueForFilePromiseProvider:(NSFilePromiseProvider*)filePromiseProvider {
    return _queue;
}

@end
