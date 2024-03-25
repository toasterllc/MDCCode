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
#import "Code/Lib/Toastbox/Mac/Renderer.h"
#import "Code/Lib/Toastbox/Signal.h"

namespace MDCStudio::ImageExporter {

// Single image export to file `filePath`
inline void __Export(Toastbox::Renderer& renderer, const Format* fmt, const ImageRecord& rec, const Image& image,
    const std::filesystem::path& filePath) {
    
    printf("Export image id %ju to %s\n", (uintmax_t)rec.info.id, filePath.c_str());
    using namespace Toastbox;
    using namespace MDCTools;
    using namespace MDCTools::ImagePipeline;
    
    Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
        image.width, image.height, (ImagePixel*)(image.data.get()));
    
//    Renderer::Txt rgbTxt = renderer.textureCreate(MTLPixelFormatRGBA8Unorm_sRGB,
//        image.width, image.height);
    
    Renderer::Txt rgbTxt = renderer.textureCreate(MTLPixelFormatRGBA16Float,
        image.width, image.height);
    
    const Pipeline::Options popts = PipelineOptionsForImage(rec, image);
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
inline void _Export(Toastbox::Renderer& renderer, ImageSourcePtr imageSource, const Format* fmt,
    const ImageRecordPtr& rec, const std::filesystem::path& filePath) {
    
    Image image = imageSource->getImage(ImageSource::Priority::High, rec);
    __Export(renderer, fmt, *rec, image, filePath);
}

inline void _Export(ImageSourcePtr imageSource, const ImageExporter::Format* fmt,
    const std::filesystem::path& path, const ImageSet& recs, std::function<bool()> progress) {
    
    constexpr const char* FilenamePrefix = "Image-";
    
    assert(recs.size() > 0);
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    Toastbox::Renderer renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    if (recs.size() > 1) {
        for (auto it=recs.rbegin(); it!=recs.rend(); it++) @autoreleasepool {
            ImageRecordPtr rec = *it;
            const std::filesystem::path filePath = path /
                (FilenamePrefix + std::to_string(rec->info.id) + "." + fmt->extension);
            
            _Export(renderer, imageSource, fmt, rec, filePath);
            if (!progress()) break;
        }
    
    } else {
        _Export(renderer, imageSource, fmt, *recs.begin(), path);
    }
}

inline void Export(NSWindow* window, ImageSourcePtr imageSource, const ImageSet& recs) {
    constexpr const char* FilenamePrefix = "Image-";
    assert(!recs.empty());
    const bool batch = recs.size()>1;
    ImageRecordPtr firstImage = *recs.begin();
    
    NSString* filename = [NSString stringWithFormat:@"%s%@", FilenamePrefix, @(firstImage->info.id)];
    ImageExportSaveDialog::Show(window, batch, filename, [=] (auto res) {
        // Only show progress dialog if we're exporting a significant number of images
        ImageExportProgressDialog* progress = nil;
        const size_t recsSize = recs.size();
        if (recsSize > 3) {
            progress = [ImageExportProgressDialog new];
            [progress setImageCount:recsSize];
            [window beginSheet:[progress window] completionHandler:nil];
        }
        
        std::thread exportThread([=] {
            size_t completed = 0;
            _Export(imageSource, res.format, [res.path UTF8String], recs, [=, &completed] {
                if (!progress) return true;
                // Signal main thread to update progress bar
                completed++;
                const float p = (float)completed / recsSize;
                dispatch_async(dispatch_get_main_queue(), ^{ [progress setProgress:p]; });
                return ![progress canceled];
            });
            
            // Close the sheet
            if (progress) {
                dispatch_async(dispatch_get_main_queue(), ^{
//                    printf("Closing progress sheet\n");
                    [window endSheet:[progress window]];
                });
            }
        });
        exportThread.detach();
    });
}

} // namespace MDCStudio::ImageExporter
