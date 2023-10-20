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
    const std::filesystem::path& dirPath) {
    
    for (ImageRecordPtr rec : recs) {
        const std::filesystem::path filePath = dirPath / (std::to_string(rec->info.id) + "." + fmt->extension);
        Export(imageSource, fmt, rec, filePath);
    }
}

inline void Export(NSWindow* window, ImageSourcePtr imageSource, const ImageSet& recs) {
    assert(!recs.empty());
    const bool batch = recs.size()>1;
    
    __block const Format* fmt = nullptr;
    __block NSString* nspath;
    __block bool done = false;
    ImageExportDialog::Show(window, batch, ^(const Format* f, NSString *p) {
        fmt = f;
        nspath = p;
        done = true;
    });
    
    while (!done) {
        [[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    
    // Bail if user cancelled the NSSavePanel
    if (!fmt) return;
    
    const std::filesystem::path path = [nspath UTF8String];
    if (batch) {
        Export(imageSource, fmt, recs, path);
    } else {
        Export(imageSource, fmt, *recs.begin(), path);
    }
}

} // namespace MDCStudio::ImageExporter
