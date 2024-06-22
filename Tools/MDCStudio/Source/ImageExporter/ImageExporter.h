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
#import "Code/Lib/Toastbox/RuntimeError.h"
#import "Code/Lib/Toastbox/TIFF.h"
#import "Code/Lib/tinydng/tiny_dng_writer.h"

namespace MDCStudio::ImageExporter {

inline struct timeval _TimevalForTimeInstant(Time::Instant t) {
    const auto tpDevice = Time::Clock::TimePointFromTimeInstant(t);
    const auto tpSystem = date::clock_cast<std::chrono::system_clock>(tpDevice);
    std::chrono::microseconds usec = tpSystem.time_since_epoch();
    const std::chrono::seconds sec = std::chrono::duration_cast<std::chrono::seconds>(usec);
    usec -= sec;
    return {
        .tv_sec = (__darwin_time_t)sec.count(),
        .tv_usec = (__darwin_suseconds_t)usec.count(),
    };
}

// Single image export to file `filePath`
inline void __Export(Toastbox::Renderer& renderer, const Format* fmt, const ImageRecord& rec, const Image& image,
    const std::filesystem::path& filePath) {
    
    printf("Export image id %ju to %s\n", (uintmax_t)rec.info.id, filePath.c_str());
    using namespace Toastbox;
    using namespace ImagePipeline;
    
    if (fmt==&Formats::JPEG || fmt==&Formats::PNG) {
        Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
            image.width, image.height, (Img::Pixel*)(image.data.get()));
        
        Renderer::Txt rgbTxt = renderer.textureCreate(MTLPixelFormatRGBA16Unorm,
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
    
    } else if (fmt == &Formats::DNG) {
        const size_t imageDataLen = image.width*image.height*sizeof(*image.data.get());
        
        TIFF tiff;
        
        // Push header
        TIFF::Val<uint32_t> nextIFDOffset;
        tiff.push((uint16_t)0x4949);
        tiff.push((uint16_t)0x002A);
        tiff.push(nextIFDOffset);
        
        // IFD0
        TIFF::Val<uint32_t> exifOffset;
        TIFF::Val<uint32_t> imageDataOffset;
        {
            tiff.set(nextIFDOffset, tiff.off());
            
            uint16_t tc = 0;
            TIFF::Val<uint16_t> tagCount;
            TIFF::Val<uint32_t> colorMatrixPointer1;
            TIFF::Val<uint32_t> colorMatrixPointer2;
            TIFF::Val<uint32_t> asShotNeutralPointer;
            
            tiff.push(tagCount);
            tiff.push( 254,   TIFF::Long,       1, 0x00000000 );                tc++; // SubFiletype
            tiff.push( 256,   TIFF::Long,       1, (uint32_t)image.width );     tc++; // ImageWidth
            tiff.push( 257,   TIFF::Long,       1, (uint32_t)image.height );    tc++; // ImageLength
            tiff.push( 258,   TIFF::Short,      1, 0x00000010 );                tc++; // BitsPerSample
            tiff.push( 259,   TIFF::Short,      1, 0x00000001 );                tc++; // Compression
            tiff.push( 262,   TIFF::Short,      1, 0x00008023 );                tc++; // PhotometricInterpretation
            tiff.push( 273,   TIFF::Long,       1, imageDataOffset );           tc++; // StripOffsets
            tiff.push( 277,   TIFF::Short,      1, 0x00000001 );                tc++; // SamplesPerPixel
            tiff.push( 278,   TIFF::Long,       1, (uint32_t)image.height );    tc++; // RowsPerStrip
            tiff.push( 279,   TIFF::Long,       1, (uint32_t)imageDataLen );    tc++; // StripByteCounts
            tiff.push( 284,   TIFF::Short,      1, 0x00000001 );                tc++; // PlanarConfig
            tiff.push( 339,   TIFF::Short,      1, 0x00000001 );                tc++; // SampleFormat
            tiff.push( 33421, TIFF::Short,      2, 0x00020002 );                tc++; // CFARepeatPatternDim
            tiff.push( 33422, TIFF::Byte,       4, 0x01020001 );                tc++; // CFAPattern
            tiff.push( 34665, TIFF::Long,       1, exifOffset );                tc++; // EXIFIFD
            tiff.push( 50706, TIFF::Byte,       4, 0x00000601 );                tc++; // DNGVersion
            tiff.push( 50714, TIFF::Short,      1, 0x00000000 );                tc++; // BlackLevel
            tiff.push( 50717, TIFF::Short,      1, Img::PixelMax );             tc++; // WhiteLevel
            tiff.push( 50721, TIFF::SRational,  9, colorMatrixPointer1 );       tc++; // ColorMatrix1
            tiff.push( 50722, TIFF::SRational,  9, colorMatrixPointer2 );       tc++; // ColorMatrix2
            tiff.push( 50728, TIFF::Rational,   3, asShotNeutralPointer );      tc++; // AsShotNeutral
            tiff.push( 50778, TIFF::Short,      1, 0x00000011 );                tc++; // CalibrationIlluminant1
            tiff.push( 50779, TIFF::Short,      1, 0x00000015 );                tc++; // CalibrationIlluminant2
            tiff.push(nextIFDOffset);
            tiff.set(tagCount, tc);
            
            // ColorMatrix1
            {
                ColorMatrix ccm = ColorMatrixForInterpolation(0).matrix.inv();
                tiff.set(colorMatrixPointer1, tiff.off());
                tiff.push(ccm.beginRow(), ccm.endRow());
            }
            
            // ColorMatrix2
            {
                ColorMatrix ccm = ColorMatrixForInterpolation(1).matrix.inv();
                tiff.set(colorMatrixPointer2, tiff.off());
                tiff.push(ccm.beginRow(), ccm.endRow());
            }
            
            // AsShotNeutral
            {
                tiff.set(asShotNeutralPointer, tiff.off());
                tiff.push(std::begin(rec.info.illumEst), std::end(rec.info.illumEst));
            }
        }
        
        // ExifIFD
        {
            tiff.set(nextIFDOffset, tiff.off());
            tiff.set(exifOffset, tiff.off());
            
            uint16_t tc = 0;
            TIFF::Val<uint16_t> tagCount;
            TIFF::Val<uint32_t> dateTimeOriginalPointer;
            TIFF::Val<uint32_t> offsetTimeOriginalPointer;
            constexpr size_t DateTimeOriginalLen = 20;
            constexpr size_t OffsetTimeOriginalLen = 7;
            
            tiff.push(tagCount);
            tiff.push( 36864, TIFF::Undefined,  4,                      0x32333230 );                   tc++; // EXIF version
            tiff.push( 36867, TIFF::ASCII,      DateTimeOriginalLen,    dateTimeOriginalPointer );      tc++; // DateTimeOriginal
            tiff.push( 36881, TIFF::ASCII,      OffsetTimeOriginalLen,  offsetTimeOriginalPointer );    tc++; // OffsetTimeOriginal
            tiff.push(nextIFDOffset);
            tiff.set(tagCount, tc);
            
            // DateTimeOriginal
            {
                const std::string str = Calendar::TimestampEXIFString(rec.info.timestamp);
                assert(str.size()+1 == DateTimeOriginalLen);
                tiff.set(dateTimeOriginalPointer, tiff.off());
                tiff.push(str.c_str(), str.c_str()+DateTimeOriginalLen);
            }
            
            // OffsetTimeOriginal
            {
                const std::string str = Calendar::TimestampOffsetEXIFString(rec.info.timestamp);
                assert(str.size()+1 == OffsetTimeOriginalLen);
                tiff.set(offsetTimeOriginalPointer, tiff.off());
                tiff.push(str.c_str(), str.c_str()+OffsetTimeOriginalLen);
            }
        }
        
        {
            // Terminate IFDs
            tiff.set(nextIFDOffset, (uint32_t)0);
        }
        
        // Image data
        {
            tiff.set(imageDataOffset, tiff.off());
            tiff.push(image.data.get(), imageDataLen);
        }
        
        tiff.write(filePath);
    
    } else {
        abort();
    }
    
    struct timeval tv = _TimevalForTimeInstant(rec.info.timestamp);
    const struct timeval times[] = { tv, tv };
    int ir = utimes(filePath.c_str(), times);
    if (ir) throw Toastbox::RuntimeError("utimes failed: %s", strerror(errno));
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
