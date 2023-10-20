#pragma once
#import <filesystem>
#import "ImageSource.h"
#import "ImageLibrary.h"
#import "ImageExportDialog/ImageExportDialog.h"
#import "ImageExporterTypes.h"

namespace MDCStudio::ImageExporter {

// Single image export to file `filePath`
inline void Export(const Format* fmt, const ImageRecord& rec, const Image& image,
    const std::filesystem::path& filePath) {
    printf("Export image id %ju to %s\n", (uintmax_t)rec.info.id, filePath.c_str());
}

// Single image export to file `filePath`
inline void Export(ImageSourcePtr imageSource, const Format* fmt,
    const ImageRecordPtr& rec, const std::filesystem::path& filePath) {
    
    Image image = imageSource->getCachedImage(rec);
    if (!image) {
        image = imageSource->loadImage(ImageSource::Priority::High, rec);
    }
    Export(fmt, *rec, image, filePath);
}

// Batch export to directory `dirPath`
inline void Export(ImageSourcePtr imageSource, const Format* fmt, const ImageSet& recs,
    const std::filesystem::path& dirPath, const std::string filenamePrefix) {
    
    for (ImageRecordPtr rec : recs) {
        const std::filesystem::path filePath = dirPath / (filenamePrefix + std::to_string(rec->info.id) + "." + fmt->extension);
        Export(imageSource, fmt, rec, filePath);
    }
}

inline void Export(NSWindow* window, ImageSourcePtr imageSource, const ImageSet& recs) {
    constexpr const char* FilenamePrefix = "Image-";
    assert(!recs.empty());
    const bool batch = recs.size()>1;
    ImageRecordPtr firstImage = *recs.begin();
    
    NSString* filename = [NSString stringWithFormat:@"%s%@", FilenamePrefix, @(firstImage->info.id)];
    auto res = ImageExportDialog::Run(window, batch, filename);
    // Bail if user cancelled the NSSavePanel
    if (!res) return;
    
    const std::filesystem::path path = [res->path UTF8String];
    if (batch) {
        Export(imageSource, res->format, recs, path, FilenamePrefix);
    } else {
        Export(imageSource, res->format, firstImage, path);
    }
}

} // namespace MDCStudio::ImageExporter
