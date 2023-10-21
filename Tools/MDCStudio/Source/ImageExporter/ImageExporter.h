#pragma once
#import <filesystem>
#import <thread>
#import "ImageSource.h"
#import "ImageLibrary.h"
#import "ImageExportSaveDialog/ImageExportSaveDialog.h"
#import "ImageExportProgressDialog/ImageExportProgressDialog.h"
#import "ImageExporterTypes.h"
#import "ImagePipelineUtil.h"
#import "Calendar.h"
#import "Tools/Shared/Renderer.h"
#import "Code/Lib/Toastbox/Signal.h"

namespace MDCStudio::ImageExporter {

// Single image export to file `filePath`
inline void __Export(MDCTools::Renderer& renderer, const Format* fmt, const ImageRecord& rec, const Image& image,
    const std::filesystem::path& filePath) {
    printf("Export image id %ju to %s\n", (uintmax_t)rec.info.id, filePath.c_str());
    using namespace MDCTools;
    using namespace MDCTools::ImagePipeline;
    
    Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
        image.width, image.height, (ImagePixel*)(image.data.get()));
    
//    Renderer::Txt rgbTxt = renderer.textureCreate(MTLPixelFormatRGBA8Unorm_sRGB,
//        image.width, image.height);
    
    Renderer::Txt rgbTxt = renderer.textureCreate(MTLPixelFormatRGBA16Float,
        image.width, image.height);
    
    const Pipeline::Options popts = PipelineOptionsForImage(rec.options, image);
    Pipeline::Run(renderer, popts, rawTxt, rgbTxt);
    
    id cgimage = renderer.imageCreate(rgbTxt);
    
    NSURL* url = [NSURL fileURLWithPath:@(filePath.c_str())];
    id /* CGImageDestinationRef */ imageDest = CFBridgingRelease(CGImageDestinationCreateWithURL((CFURLRef)url,
        (CFStringRef)fmt->uti, 1, nil));
    
    id /* CGMutableImageMetadataRef */ metadata = CFBridgingRelease(CGImageMetadataCreateMutable());
    
    CGImageMetadataSetValueMatchingImageProperty((CGMutableImageMetadataRef)metadata,
        kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal,
        (CFTypeRef)@(Calendar::TimestampEXIFString(rec.info.timestamp).c_str()));
    
    CGImageMetadataSetValueMatchingImageProperty((CGMutableImageMetadataRef)metadata,
        kCGImagePropertyExifDictionary, kCGImagePropertyExifOffsetTimeOriginal,
        (CFTypeRef)@(Calendar::TimestampOffsetEXIFString(rec.info.timestamp).c_str()));
    
    CGImageDestinationAddImageAndMetadata((CGImageDestinationRef)imageDest, (CGImageRef)cgimage,
        (CGImageMetadataRef)metadata, nullptr);
    CGImageDestinationFinalize((CGImageDestinationRef)imageDest);
}

// Single image export to file `filePath`
inline void _Export(MDCTools::Renderer& renderer, ImageSourcePtr imageSource, const Format* fmt,
    const ImageRecordPtr& rec, const std::filesystem::path& filePath) {
    
    Image image = imageSource->getCachedImage(rec);
    if (!image) {
        image = imageSource->loadImage(ImageSource::Priority::High, rec);
    }
    __Export(renderer, fmt, *rec, image, filePath);
}

// Batch export to directory `dirPath`
inline void _Export(MDCTools::Renderer& renderer, ImageSourcePtr imageSource, const Format* fmt, const ImageSet& recs,
    const std::filesystem::path& dirPath, const std::string filenamePrefix, std::function<void()> progress) {
    for (ImageRecordPtr rec : recs) @autoreleasepool {
        const std::filesystem::path filePath = dirPath / (filenamePrefix + std::to_string(rec->info.id) + "." + fmt->extension);
        _Export(renderer, imageSource, fmt, rec, filePath);
        progress();
    }
}

inline void Export(NSWindow* window, ImageSourcePtr imageSource, const ImageSet& recs) {
    constexpr const char* FilenamePrefix = "Image-";
    assert(!recs.empty());
    const bool batch = recs.size()>1;
    ImageRecordPtr firstImage = *recs.begin();
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MDCTools::Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    NSString* filename = [NSString stringWithFormat:@"%s%@", FilenamePrefix, @(firstImage->info.id)];
    auto res = ImageExportSaveDialog::Run(window, batch, filename);
    // Bail if user cancelled the NSSavePanel
    if (!res) return;
    
    ImageExportProgressDialog* progress = [ImageExportProgressDialog new];
    
//    struct {
//        Toastbox::Signal signal;
//        size_t completed = 0;
//    } status;
    
    std::thread exportThread([&] {
        const std::filesystem::path path = [res->path UTF8String];
        if (batch) {
            size_t completed = 0;
            _Export(renderer, imageSource, res->format, recs, path, FilenamePrefix, [&] {
                completed++;
                const float progress = (float)completed / recs.size();
                dispatch_async(dispatch_get_main_queue(), ^{
                    [progress setProgress:progress];
                });
            });
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSApp stopModalWithCode:NSModalResponseStop];
            });
        } else {
            _Export(renderer, imageSource, res->format, firstImage, path);
        }
    });
    
    // Show the modal progress dialog
    {
        NSWindow* progressWindow = [progress window];
        [window beginSheet:progressWindow completionHandler:nil];
        
        NSModalSession session = [NSApp beginModalSessionForWindow:progressWindow];
        for (;;) {
            if ([NSApp runModalSession:session] != NSModalResponseContinue) break;
            
            [self doSomeWork];
        }
        [NSApp endModalSession:session];
        
        [window endSheet:progressWindow];
    }
    
    exportThread.join();
    
    
//    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
//        [NSApp stopModalWithCode:result];
//    }];
//    
//    const NSModalResponse response = [panel runModal];
//    if (response != NSModalResponseOK) return std::nullopt;
}

} // namespace MDCStudio::ImageExporter
