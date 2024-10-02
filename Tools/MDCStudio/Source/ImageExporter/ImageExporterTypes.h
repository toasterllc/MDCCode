#pragma once
#include <string_view>

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
    
    static const Format& FormatForName(const char* name) {
        assert(name);
        for (const Format* fmt : All) {
            if (std::string_view(name) == fmt->name) {
                return *fmt;
            }
        }
        abort();
    }
};

} // namespace MDCStudio::ImageExporter
