#pragma once
#import <filesystem>
#import <thread>
#import <queue>
#import "ImageExportSaveDialog/ImageExportSaveDialog.h"
#import "ImageExportProgressDialog/ImageExportProgressDialog.h"
#import "ImageExporterTypes.h"
#import "ImagePipelineUtil.h"
#import "Calendar.h"
#import "Lib/Toastbox/Mac/Renderer.h"
#import "Lib/Toastbox/Signal.h"
#import "Lib/Toastbox/RuntimeError.h"
#import "Lib/Toastbox/TIFF.h"
#import "Shared/ImageSource.h"
#import "Shared/ImageLibrary.h"

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

inline void _WhiteBalanceApply(ColorMatrix& m, const double* wb) {
    for (int y=0; y<3; y++) {
        for (int x=0; x<3; x++) {
            m.at(y,x) /= wb[x];
        }
    }
}

inline std::string _ExifImageUniqueIDForImageId(Img::Id id) {
    char buf[48];
    snprintf(buf, sizeof(buf), "%032jX", (uintmax_t)id);
    return buf;
}

// Single image export to file `filePath`
inline void Export(Toastbox::Renderer& renderer, const ImageRecord& rec, const Image& image,
    const Format& fmt, const std::filesystem::path& filePath) {
    
    printf("Export image id %ju to %s\n", (uintmax_t)rec.info.id, filePath.c_str());
    using namespace Toastbox;
    using namespace ImagePipeline;
    
    const Time::Instant timestamp = rec.info.timestamp;
    const float batteryLevel = MSP::BatteryLevelFloat(MSP::BatteryLevelLinearize(rec.info.batteryLevelMv));
    
    if (&fmt==&Formats::JPEG || &fmt==&Formats::PNG) {
        Renderer::Txt rawTxt = Pipeline::TextureForRaw(renderer,
            image.width, image.height, (Img::Pixel*)(image.data.get()));
        
        Renderer::Txt rgbTxt = renderer.textureCreate(MTLPixelFormatRGBA16Unorm,
            image.width, image.height);
        
        const Pipeline::Options popts = PipelineOptionsForImage(rec, image);
        Pipeline::Run(renderer, popts, rawTxt, rgbTxt);
        
        id cgimage = renderer.imageCreate(rgbTxt, true);
        
        NSURL* url = [NSURL fileURLWithPath:@(filePath.c_str())];
        id /* CGImageDestinationRef */ imageDest = CFBridgingRelease(CGImageDestinationCreateWithURL((CFURLRef)url,
            (CFStringRef)fmt.uti, 1, nil));
        
        id /* CGMutableImageMetadataRef */ metadata = CFBridgingRelease(CGImageMetadataCreateMutable());
        
        if (Time::Absolute(timestamp)) {
            CGImageMetadataSetValueMatchingImageProperty((CGMutableImageMetadataRef)metadata,
                kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal,
                (CFTypeRef)@(Calendar::TimestampEXIFString(timestamp).c_str()));
            
            CGImageMetadataSetValueMatchingImageProperty((CGMutableImageMetadataRef)metadata,
                kCGImagePropertyExifDictionary, kCGImagePropertyExifOffsetTimeOriginal,
                (CFTypeRef)@(Calendar::TimestampOffsetEXIFString(timestamp).c_str()));
        }
        
        CGImageMetadataSetValueMatchingImageProperty((CGMutableImageMetadataRef)metadata,
            kCGImagePropertyExifDictionary, kCGImagePropertyExifImageUniqueID,
            (CFTypeRef)@(_ExifImageUniqueIDForImageId(rec.info.id).c_str()));
        
        // No kCGImagePropertyExifBatteryLevel key, and manually specifying "BatteryLevel" doesn't work
//        CGImageMetadataSetValueMatchingImageProperty((CGMutableImageMetadataRef)metadata,
//            kCGImagePropertyExifDictionary, CFSTR("BatteryLevel"),
//            (CFTypeRef)@(batteryLevel));
        
        CGImageDestinationAddImageAndMetadata((CGImageDestinationRef)imageDest, (CGImageRef)cgimage,
            (CGImageMetadataRef)metadata, nullptr);
        CGImageDestinationFinalize((CGImageDestinationRef)imageDest);
    
    } else if (&fmt == &Formats::DNG) {
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
            TIFF::Val<uint32_t> batteryLevelPointer;
            TIFF::Val<uint32_t> colorMatrixPointer1;
            TIFF::Val<uint32_t> colorMatrixPointer2;
            TIFF::Val<uint32_t> asShotNeutralPointer;
            
            tiff.push(tagCount);
            tiff.push( 254,   TIFF::Long,       1, 0x00000000 );                            tc++; // SubFiletype
            tiff.push( 256,   TIFF::Long,       1, (uint32_t)image.width );                 tc++; // ImageWidth
            tiff.push( 257,   TIFF::Long,       1, (uint32_t)image.height );                tc++; // ImageLength
            tiff.push( 258,   TIFF::Short,      1, 0x00000010 );                            tc++; // BitsPerSample
            tiff.push( 259,   TIFF::Short,      1, 0x00000001 );                            tc++; // Compression
            tiff.push( 262,   TIFF::Short,      1, 0x00008023 );                            tc++; // PhotometricInterpretation
            tiff.push( 273,   TIFF::Long,       1, imageDataOffset );                       tc++; // StripOffsets
            tiff.push( 277,   TIFF::Short,      1, 0x00000001 );                            tc++; // SamplesPerPixel
            tiff.push( 278,   TIFF::Long,       1, (uint32_t)image.height );                tc++; // RowsPerStrip
            tiff.push( 279,   TIFF::Long,       1, (uint32_t)imageDataLen );                tc++; // StripByteCounts
            tiff.push( 284,   TIFF::Short,      1, 0x00000001 );                            tc++; // PlanarConfig
            tiff.push( 339,   TIFF::Short,      1, 0x00000001 );                            tc++; // SampleFormat
            tiff.push( 33421, TIFF::Short,      2, 0x00020002 );                            tc++; // CFARepeatPatternDim
            tiff.push( 33422, TIFF::Byte,       4, 0x01020001 );                            tc++; // CFAPattern
            tiff.push( 33423, TIFF::Rational,   1, batteryLevelPointer );                   tc++; // BatteryLevel
            tiff.push( 34665, TIFF::Long,       1, exifOffset );                            tc++; // EXIFIFD
            tiff.push( 50706, TIFF::Byte,       4, 0x00000601 );                            tc++; // DNGVersion
            tiff.push( 50714, TIFF::Short,      1, 0x00000000 );                            tc++; // BlackLevel
            tiff.push( 50717, TIFF::Short,      1, Img::PixelMax );                         tc++; // WhiteLevel
            tiff.push( 50721, TIFF::SRational,  9, colorMatrixPointer1 );                   tc++; // ColorMatrix1
            tiff.push( 50722, TIFF::SRational,  9, colorMatrixPointer2 );                   tc++; // ColorMatrix2
            tiff.push( 50728, TIFF::Rational,   3, asShotNeutralPointer );                  tc++; // AsShotNeutral
            tiff.push( 50778, TIFF::Short,      1, 0x00000011 );                            tc++; // CalibrationIlluminant1 (StandardA)
            tiff.push( 50779, TIFF::Short,      1, 0x00000017 );                            tc++; // CalibrationIlluminant2 (D50)
            tiff.push(nextIFDOffset);
            tiff.set(tagCount, tc);
            
            // BatteryLevel
            {
                tiff.set(batteryLevelPointer, tiff.off());
                tiff.push(batteryLevel);
            }
            
            const auto& illumOrig = rec.options.whiteBalance.illum;
            const double illumMax = std::max(std::max(illumOrig[0], illumOrig[1]), illumOrig[2]);
            const double illum[3] = {
                illumOrig[0]/illumMax,
                illumOrig[1]/illumMax,
                illumOrig[2]/illumMax,
            };
            
            {
                // ColorMatrix1
                {
                    ColorMatrix ccm = ColorMatrixForInterpolation(0).matrix;
                    _WhiteBalanceApply(ccm, illum);
                    ccm = ccm.inv();
                    
                    tiff.set(colorMatrixPointer1, tiff.off());
                    tiff.push(ccm.beginRow(), ccm.endRow());
                }
                
                // ColorMatrix2
                {
                    ColorMatrix ccm = ColorMatrixForInterpolation(1).matrix;
                    _WhiteBalanceApply(ccm, illum);
                    ccm = ccm.inv();
                    
                    tiff.set(colorMatrixPointer2, tiff.off());
                    tiff.push(ccm.beginRow(), ccm.endRow());
                }
            }
            
            // AsShotNeutral
            {
                tiff.set(asShotNeutralPointer, tiff.off());
                tiff.push(std::begin(illum), std::end(illum));
            }
        }
        
        {
            // Terminate IFDs
            tiff.set(nextIFDOffset, (uint32_t)0);
        }
        
        // ExifIFD subdirectory
        {
            tiff.set(exifOffset, tiff.off());
            
            uint16_t tc = 0;
            TIFF::Val<uint16_t> tagCount;
            TIFF::Val<uint32_t> dateTimeOriginalPointer;
            TIFF::Val<uint32_t> offsetTimeOriginalPointer;
            TIFF::Val<uint32_t> imageUniqueIDPointer;
            constexpr size_t DateTimeOriginalLen = 19+1; // +1 for null byte
            constexpr size_t OffsetTimeOriginalLen = 6+1; // +1 for null byte
            constexpr size_t ImageUniqueIDLen = 32+1; // +1 for null byte
            
            tiff.push(tagCount);
            tiff.push( 36864, TIFF::Undefined,  4,                      0x32333230 );                       tc++; // EXIF version
            
            if (Time::Absolute(timestamp)) {
                tiff.push( 36867, TIFF::ASCII,      DateTimeOriginalLen,    dateTimeOriginalPointer );      tc++; // DateTimeOriginal
                tiff.push( 36881, TIFF::ASCII,      OffsetTimeOriginalLen,  offsetTimeOriginalPointer );    tc++; // OffsetTimeOriginal
            }
            
            tiff.push( 40962, TIFF::Long,       1,                      (uint32_t)image.width );            tc++; // ExifImageWidth
            tiff.push( 40963, TIFF::Long,       1,                      (uint32_t)image.height );           tc++; // ExifImageHeight
            tiff.push( 42016, TIFF::ASCII,      ImageUniqueIDLen,       imageUniqueIDPointer );             tc++; // ImageUniqueID
            tiff.push(nextIFDOffset);
            tiff.set(tagCount, tc);
            
            if (Time::Absolute(timestamp)) {
                // DateTimeOriginal
                {
                    const std::string str = Calendar::TimestampEXIFString(timestamp);
                    assert(str.size()+1 == DateTimeOriginalLen);
                    tiff.set(dateTimeOriginalPointer, tiff.off());
                    tiff.push(str.c_str(), str.c_str()+DateTimeOriginalLen);
                }
                
                // OffsetTimeOriginal
                {
                    const std::string str = Calendar::TimestampOffsetEXIFString(timestamp);
                    assert(str.size()+1 == OffsetTimeOriginalLen);
                    tiff.set(offsetTimeOriginalPointer, tiff.off());
                    tiff.push(str.c_str(), str.c_str()+OffsetTimeOriginalLen);
                }
            }
            
            // ImageUniqueID
            {
                const std::string str = _ExifImageUniqueIDForImageId(rec.info.id);
                assert(str.size()+1 == ImageUniqueIDLen);
                tiff.set(imageUniqueIDPointer, tiff.off());
                tiff.push(str.c_str(), str.c_str()+ImageUniqueIDLen);
            }
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
    
    if (Time::Absolute(timestamp)) {
        struct timeval tv = _TimevalForTimeInstant(timestamp);
        const struct timeval times[] = { tv, tv };
        int ir = utimes(filePath.c_str(), times);
        if (ir) throw Toastbox::RuntimeError("utimes failed: %s", strerror(errno));
    }
}

inline std::filesystem::path FileNameForImageRecord(const ImageRecord& rec, const ImageExporter::Format* fmt=nullptr) {
    char buf[32];
    snprintf(buf, sizeof(buf), "Image-%06ju%s%s", (uintmax_t)rec.info.id, (fmt ? "." : ""), (fmt ? fmt->extension : ""));
    return buf;
}

inline void Export(ImageSourcePtr imageSource, const ImageSet& recs,
    const ImageExporter::Format& fmt, const std::filesystem::path& dir,
    ImageExportProgressDialog* progress=nil) {
    
    struct ImageRec {
        Image image;
        ImageRecordPtr rec;
    };
    
    struct {
        Toastbox::Signal signal; // Protects this struct
        std::queue<ImageRec> images;
    } shared;
    
    auto timeStart = std::chrono::steady_clock::now();
    
    // ## Consumers
    // Spawn N worker threads (N=number of cores)
    std::vector<std::thread> workers;
    const int threadCount = std::min((int)recs.size(), (int)std::thread::hardware_concurrency());
    for (int i=0; i<threadCount; i++) {
        workers.emplace_back([&](){
            Toastbox::Renderer renderer;
            for (;;) @autoreleasepool {
                try {
                    ImageRec imageRec;
                    {
                        auto lock = shared.signal.wait([&] { return !shared.images.empty(); });
                        imageRec = std::move(shared.images.front());
                        shared.images.pop();
                        shared.signal.signalAll();
                    }
                    
                    const std::filesystem::path filePath = dir / FileNameForImageRecord(*imageRec.rec, &fmt);
                    Export(renderer, *imageRec.rec, imageRec.image, fmt, filePath);
                    
                    // Update progress bar
                    [progress incrementProgress];
                
                } catch (const Toastbox::Signal::Stop&) {
                    break;
                }
            }
        });
    }
    
    // ## Producer
    // Show progress dialog if it's not already shown
    [progress showIfNeeded];
    
    const size_t producerSlotCount = threadCount+8;
    for (auto it=recs.rbegin(); it!=recs.rend() && ![progress canceled]; it++) @autoreleasepool {
        ImageRecordPtr rec = *it;
        Image image = imageSource->getImage(ImageSource::Priority::Low, rec);
        
        {
            auto lock = shared.signal.wait([&] {
                return shared.images.size()<producerSlotCount;
            });
            
            shared.images.push({
                .image = std::move(image),
                .rec = rec,
            });
            
            shared.signal.signalAll();
        }
    }
    
    // Signal that there's no more data coming
    {
        auto lock = shared.signal.wait([&] { return shared.images.empty() || [progress canceled]; });
        shared.signal.stop(lock);
    }
    
    // Wait for consumers to complete
    for (std::thread& t : workers) t.join();
    
    // Print timing
    {
        using namespace std::chrono;
        const milliseconds duration = duration_cast<milliseconds>(steady_clock::now()-timeStart);
        printf("[ImageExporter::Export] export took %ju ms for %ju images\n",
            (uintmax_t)duration.count(), (uintmax_t)recs.size());
    }
}

//inline void Export(NSWindow* window,
//    ImageSourcePtr imageSource, const ImageSet& recs,
//    const ImageExporter::Format* fmt, const std::filesystem::path& path) {
//    
//    ImageExportProgressDialog* progress = [[ImageExportProgressDialog alloc] initWithParentWindow:window
//        imageCount:recs.size()];
//    
//    std::thread exportThread([=] {
//        Export(imageSource, recs, fmt, path, progress);
//    });
//    exportThread.detach();
//}

inline void Export(NSWindow* window, ImageSourcePtr imageSource, const ImageSet& recs) {
    assert(!recs.empty());
    const bool batch = recs.size()>1;
    ImageRecordPtr firstImageRec = *recs.begin();
    
    ImageExportSaveDialog::Show(window, batch, @(FileNameForImageRecord(*firstImageRec).c_str()), [=] (auto res) {
        if (batch) {
            ImageExportProgressDialog* progress = [[ImageExportProgressDialog alloc] initWithParentWindow:window
                imageCount:recs.size()];
            
            std::thread exportThread([=] {
                Export(imageSource, recs, *res.format, [res.path UTF8String], progress);
            });
            exportThread.detach();
        
        } else {
            Toastbox::Renderer renderer;
            Image image = imageSource->getImage(ImageSource::Priority::Low, firstImageRec);
            Export(renderer, *firstImageRec, image, *res.format, [res.path UTF8String]);
            
//            Toastbox::Renderer renderer;
//            _Export(renderer, imageSource, firstImage, res.format, res.path);
            
//            Export(imageSource, firstImage, res.format, [res.path UTF8String]);
        }
    });
}

} // namespace MDCStudio::ImageExporter
