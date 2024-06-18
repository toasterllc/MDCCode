#pragma once

namespace MDCStudio::ImageExporter {

struct Format {
    const char* name;
    const char* extension;
    NSString* uti;
};

struct Formats {
    static const inline Format JPEG = { "JPEG", "jpg", (NSString*)kUTTypeJPEG };
    static const inline Format PNG  = { "PNG",  "png", (NSString*)kUTTypePNG };
    static const inline Format DNG  = { "DNG",  "dng", (NSString*)kUTTypeRawImage };
    static const inline Format* All[] = {
        &JPEG,
        &PNG,
        &DNG,
    };
};

} // namespace MDCStudio::ImageExporter
